# -*- encoding: utf-8 -*-
# stub: rails_stdout_logging 0.0.5 ruby lib

Gem::Specification.new do |s|
  s.name = "rails_stdout_logging".freeze
  s.version = "0.0.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["David Dollar".freeze, "Jonathan Dance".freeze, "Richard Schneeman".freeze]
  s.date = "2016-03-23"
  s.description = "Sets Rails to log to stdout".freeze
  s.email = ["david@heroku.com".freeze, "jd@heroku.com".freeze, "richard@heroku.com".freeze]
  s.homepage = "https://github.com/heroku/rails_stdout_logging".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "2.5.1".freeze
  s.summary = "Overrides Rails' built in logger to send all logs to stdout".freeze

  s.installed_by_version = "3.5.11".freeze if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<test-unit>.freeze, ["~> 3".freeze])
end
