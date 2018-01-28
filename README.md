# Ruby Proc filter plugin for Embulk

This plugin is inspired by [mgi166/embulk-filter-eval: Eval ruby code on filtering](https://github.com/mgi166/embulk-filter-eval "mgi166/embulk-filter-eval: Eval ruby code on filtering")

This plugin apply ruby proc to each record.

## Overview

* **Plugin type**: filter

## Configuration

- **columns**: filter definition (hash, required)
- **requires**: pre required libraries (array, default: `[]`)

## Example

### input
```csv
id,account,time,purchase,comment,data
1,32864,2015-01-27 19:23:49,20150127,embulk,"{\"foo\": \"bar\", \"events\": [{\"id\": 1, \"name\": \"Name1\"}, {\"id\": 2, \"name\": \"Name2\"}]}"
2,14824,2015-01-27 19:01:23,20150127,embulk jruby,NULL
3,27559,2015-01-28 02:20:02,20150128,"Embulk ""csv"" parser plugin",NULL
4,11270,2015-01-29 11:54:36,20150129,NULL,NULL
```

### config
```yaml
# ...

filters:
  - type: ruby_proc
    requires:
      - cgi
    variables:
      multiply: 3
    before:
      - proc: |
          -> do
            puts "before proc"
            @started_at = Time.now
          end
    after:
      - proc: |
          -> do
            puts "after proc"
            p Time.now - @started_at
          end
    rows:
      - proc: |
          ->(record) do
            [record.dup, record.dup.tap { |r| r["id"] += 10 }]
          end
    skip_rows:
      - proc: |
          ->(record) do
            record["id"].odd?
          end
    columns:
      - name: data
        proc: |
          ->(data) do
            data["events"] = data["events"].map.with_index do |e, idx|
              e.tap { |e_| e_["idx"] = idx }
            end
            data
          end
      - name: id
        proc: |
          ->(id) do
            id * variables["multiply"]
          end
        type: string
      - name: comment
        proc_file: comment_upcase.rb
        skip_nil: false
        type: json

# ...

```

If you want to skip record in "rows proc" or "columns proc", use `throw :skip_record`.

```rb
# comment_upcase.rb

->(comment, record) do
  return [record["account"].to_s].to_json unless comment
  comment.upcase.split(" ").map { |s| CGI.escape(s) }
end
```

- `before` and `after` is executed at once
- procs is evaluated on same binding (instance of Evaluator class)
  - instance variable is shared
- rows proc must return record hash or array of record hash.
  - user must take care of object identity. Otherwise, error may be occurred when plugin applys column procs.

### proc execution order
1. before procs
1. per record
  1. all row procs
  1. per record applied row procs
    1. all skip\_row procs
    1. column procs
1. after procs

### preview
```
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
| id:string | account:long |          time:timestamp |      purchase:timestamp |                             comment:json |                                                                                data:json |
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
|         3 |       32,864 | 2015-01-27 19:23:49 UTC | 2015-01-27 00:00:00 UTC |                               ["EMBULK"] | {"events":[{"id":1,"name":"Name1","idx":0},{"id":2,"name":"Name2","idx":1}],"foo":"bar"} |
|        33 |       32,864 | 2015-01-27 19:23:49 UTC | 2015-01-27 00:00:00 UTC |                               ["EMBULK"] | {"events":[{"id":1,"name":"Name1","idx":0},{"id":2,"name":"Name2","idx":1}],"foo":"bar"} |
|         6 |       14,824 | 2015-01-27 19:01:23 UTC | 2015-01-27 00:00:00 UTC |                       ["EMBULK","JRUBY"] |                                                                                          |
|        36 |       14,824 | 2015-01-27 19:01:23 UTC | 2015-01-27 00:00:00 UTC |                       ["EMBULK","JRUBY"] |                                                                                          |
|         9 |       27,559 | 2015-01-28 02:20:02 UTC | 2015-01-28 00:00:00 UTC | ["EMBULK","%22CSV%22","PARSER","PLUGIN"] |                                                                                          |
|        39 |       27,559 | 2015-01-28 02:20:02 UTC | 2015-01-28 00:00:00 UTC | ["EMBULK","%22CSV%22","PARSER","PLUGIN"] |                                                                                          |
|        12 |       11,270 | 2015-01-29 11:54:36 UTC | 2015-01-29 00:00:00 UTC |                                ["11270"] |                                                                                          |
|        42 |       11,270 | 2015-01-29 11:54:36 UTC | 2015-01-29 00:00:00 UTC |                                ["11270"] |                                                                                          |
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
```

## Build

```
$ rake
```
