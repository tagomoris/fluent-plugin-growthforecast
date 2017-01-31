# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-growthforecast"
  gem.version       = "0.3.0"
  gem.authors       = ["TAGOMORI Satoshi"]
  gem.email         = ["tagomoris@gmail.com"]
  gem.summary       = %q{Fluentd output plugin to post numbers to GrowthForecast (by kazeburo)}
  gem.description   = %q{For GrowthForecast, see http://kazeburo.github.com/GrowthForecast/}
  gem.homepage      = "https://github.com/tagomoris/fluent-plugin-growthforecast"
  gem.license       = "Apache-2.0"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "rake"
  gem.add_development_dependency "test-unit", ">= 3.0.0"
  gem.add_runtime_dependency "fluentd", "< 0.14.0"
  gem.add_runtime_dependency "fluent-mixin-config-placeholders", ">= 0.3.0"
  gem.add_runtime_dependency "resolve-hostname", ">= 0.0.4"
end
