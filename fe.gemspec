$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "fe/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "fe"
  s.version     = Fe::VERSION
  s.authors     = ["CruGlobal"]
  s.email       = ["programmers@cojourners.com"]
  s.homepage    = "http://cru.org"
  s.summary     = "Form Engine"
  s.description = "A rails engine that facilitates question/answer stuff"

  s.files = Dir["{app,config,db,lib}/**/*", "spec/factories/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency 'rails', '>= 5.0.7'
  s.add_dependency 'acts_as_list', '= 0.9.17'
  s.add_dependency 'aasm', '= 3.4'
  s.add_dependency 'jquery-rails'
  s.add_dependency 'jquery-ui-rails'
  s.add_dependency 'dynamic_form'
  s.add_dependency 'carmen', '~> 0.2.12'
  s.add_dependency 'validates_email_format_of'
  s.add_dependency 'liquid'
  s.add_dependency 'sass'
  s.add_dependency 'gettext_i18n_rails', '~> 1.2.3'
  s.add_dependency 'paper_trail', '~> 5.2.3'

  s.add_development_dependency "mysql2", '~> 0.5.2'
  s.add_development_dependency "rspec-rails"
  s.add_development_dependency "shoulda"
  s.add_development_dependency "factory_bot_rails"
  s.add_development_dependency 'rails-dummy'

  # https://github.com/bmabey/database_cleaner/issues/224
  # https://github.com/bmabey/database_cleaner/pull/241
  # therefore added custom branch to Gemfile
  #
  # s.add_development_dependency 'database_cleaner', '1.0.1'
end
