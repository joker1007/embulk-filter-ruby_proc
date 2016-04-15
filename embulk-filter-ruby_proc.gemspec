
Gem::Specification.new do |spec|
  spec.name          = "embulk-filter-ruby_proc"
  spec.version       = "0.6.0"
  spec.authors       = ["joker1007"]
  spec.summary       = "Ruby Proc filter plugin for Embulk"
  spec.description   = "Filter each record by ruby proc"
  spec.email         = ["kakyoin.hierophant@gmail.com"]
  spec.licenses      = ["MIT"]
  spec.homepage      = "https://github.com/joker1007/embulk-filter-ruby_proc"

  spec.files         = `git ls-files`.split("\n") + Dir["classpath/*.jar"]
  spec.test_files    = spec.files.grep(%r{^(test|spec)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'embulk', ['>= 0.8.1']
  spec.add_development_dependency 'bundler', ['>= 1.10.6']
  spec.add_development_dependency 'rake', ['>= 10.0']
end
