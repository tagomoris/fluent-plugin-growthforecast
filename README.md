# fluent-plugin-growthforecast

## GrowthForecastOutput

Plugin to output numbers(metrics) to 'GrowthForecast', metrics drawing tool over HTTP.

About GrowthForecast, see:
* Github: https://github.com/kazeburo/growthforecast
* Product site (japanese): http://kazeburo.github.com/GrowthForecast/
* Japanese blog post by @kazeburo: http://blog.nomadscafe.jp/2011/12/growthforecast.html

GrowthForecast is very simple and powerful tool to draw graphs what we want, with GrowthForecastOutput and Fluentd.

### Configuration

For messages such as:
    tag:metrics {"field1":300, "field2":20, "field3diff":-30}
    
Configuration example for graphs in growthforecast with POST api url 'http://growthforecast.local/api/service1/metrics1/metrics_FIELDNAME'.

    <match metrics>
      type growthforecast
      gfapi_url http://growthforecast.local/api/
      service   service1
      section   metrics1
      name_keys field1,field2,field3diff
    </match>

With this configuration, out_growthforecast posts urls below.

    http://growthforecast.local/api/service1/metrics1/metrics_field1
    http://growthforecast.local/api/service1/metrics1/metrics_field2
    http://growthforecast.local/api/service1/metrics1/metrics_field3diff

If you want to use tags for `section` or `service`  in GrowthForecast, use `tag_for` options and `remove_prefix` (and not to set the `section` or `service` that the value of 'tag_for' used to.).

    <match metrics.**>
      type growthforecast
      gfapi_url http://growthforecast.local/api/
      service   service1
      name_keys field1,field2,field3diff
      tag_for   section    # or 'name_prefix'(default) or 'ignore' or 'service'
      remove_prefix metrics
    </match>

`mode` option available with `gauge`(default), `count`, `modified`, just same as `mode` of GrowthForecast POST parameter.

`name_key_pattern REGEXP` available instead of `name_keys` like this:

    <match metrics.**>
      type growthforecast
      gfapi_url http://growthforecast.local/api/
      service   service1
      tag_for   section    # or 'name_prefix'(default) or 'ignore' or 'service'
      remove_prefix metrics
      name_key_pattern ^(field|key)\d+$
    </match>

This configuration matches only with metrics.field1, metrics.key20, .... and doesn't match with metrics.field or metrics.foo.

If your GrowthForecast protected with basic authentication, specify `authentication` option:

    <match metrics.**>
      type growthforecast
      gfapi_url http://growthforecast.protected.anywhere.example.com/api/
      service   yourservice
      tag_for   section
      name_keys fieldname
      authentication basic
      username yourusername
      password secret!
    </match>

Version v0.2.0 or later, this plugin uses HTTP connection keep-alive for a batch emitted events. To disable this, specify `keepalive` option:

    <match metrics.**>
      type growthforecast
      gfapi_url http://growthforecast.protected.anywhere.example.com/api/
      service   yourservice
      tag_for   section
      name_keys fieldname
	  keepalive no
    </match>

## Parameters

* gfapi\_url (required)

    The URL of a GrowthForecast API endpoint like `http://growth.forecast.local/api/`.
    
* tag\_for

    Either of `name_prefix`, `section`, `service`, or `ignore`. Default is `name_prefix`. 

    * `name_prefix` uses the tag name as a graph\_name prefix. 
    * `section` uses the tag name as a section\_name.
    * `service` uses the tag name as a service\_name.
    * `ignore` uses the tag name for nothing.
    
* remove\_prefix

    The prefix string which will be removed from the tag. This option would be useful using with the `tag_for` option.

* service

    The service\_name of graphs to create.

* section

    The section\_name of graphs to create.

* name\_keys

    Specify field names of the input record. Separate by , (comma).
    The values of these fields are posted as numbers, and names of thease fields are used as parts of grame\_names. 
    Either of `name_keys` or `name_key_pattern` is required. 

* name\_key\_pattern

    Specify the field names of the input record by a regular expression.
    The values of these fields are posted as numbers, and names of thease fields are used as parts of grame\_names. 
    Either of `name_keys` or `name_key_pattern` is required. 

* graphs

    You may use this option to specify graph names correspond to each of `name_keys`. Separate by , (comma). 
    The number of graph names must be same with the number of `name_keys`.

* mode

    The graph mode (either of `gauge`, `count`, or `modified`). Just same as `mode` of GrowthForecast POST parameter. Default is `gauge`. 
    
* keepalive

    Use a keepalive HTTP connection. Default is false.

    NOTE: To effectively use this, you may need to give a parameter `max_keepalive_reqs` (default: 1) to Starlet in `growthforecast.pl`. 
    
* background_post

    Post to GrowthForecast in background thread, without retries for failures (Default: false)

* timeout

    Read/Write timeout seconds (Default: 60)

* retry

    Do retry for HTTP request failures, or not. This feature will be set as false for `background_post yes` automatically. (Default: true)

* ssl

    Use SSL (https) or not. Default is false. 
    
* verify\_ssl

    Do SSL verification or not. Default is false (ignore the SSL verification).

* authentication

    Specify `basic` if your GrowthForecast protected with basic authentication. Default is 'none' (no authentication).
    
* username

    The username for authentication.

* password

    The password for authentication.

## TODO

* patches welcome!

## Copyright

* Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
