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

## TODO

* patches welcome!

## Copyright

* Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
