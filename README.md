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
    columns:
      - name: data
        proc: |
          ->(data) do
            data["events"] = data["events"].map.with_index do |e, idx|
              e.tap { |e_| e_["idx"] = idx }
            end
            data.to_json
          end
      - name: id
        proc: |
          ->(id) do
            id * 2
          end
        type: string
      - name: comment
        proc: |
          ->(comment, record) do
            return [record["account"].to_s].to_json unless comment
            comment.upcase.split(" ").map { |s| CGI.escape(s) }.to_json
          end
        skip_nil: false
        type: json
    target: events

# ...

```

### preview
```
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
| id:string | account:long |          time:timestamp |      purchase:timestamp |                             comment:json |                                                                                data:json |
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
|         2 |       32,864 | 2015-01-27 19:23:49 UTC | 2015-01-27 00:00:00 UTC |                               ["EMBULK"] | {"events":[{"id":1,"name":"Name1","idx":0},{"id":2,"name":"Name2","idx":1}],"foo":"bar"} |
|         4 |       14,824 | 2015-01-27 19:01:23 UTC | 2015-01-27 00:00:00 UTC |                       ["EMBULK","JRUBY"] |                                                                                          |
|         6 |       27,559 | 2015-01-28 02:20:02 UTC | 2015-01-28 00:00:00 UTC | ["EMBULK","%22CSV%22","PARSER","PLUGIN"] |                                                                                          |
|         8 |       11,270 | 2015-01-29 11:54:36 UTC | 2015-01-29 00:00:00 UTC |                                ["11270"] |                                                                                          |
+-----------+--------------+-------------------------+-------------------------+------------------------------------------+------------------------------------------------------------------------------------------+
```

## Build

```
$ rake
```
