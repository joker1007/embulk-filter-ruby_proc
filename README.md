# Ruby Proc filter plugin for Embulk

TODO: Write short description here and embulk-filter-ruby_proc.gemspec file.

## Overview

* **Plugin type**: filter

## Configuration

- **option1**: description (integer, required)
- **option2**: description (string, default: `"myvalue"`)
- **option3**: description (string, default: `null`)

## Example

```yaml
filters:
  - type: ruby_proc
    option1: example1
    option2: example2
```


## Build

```
$ rake
```
