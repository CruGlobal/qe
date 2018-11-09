source "https://rubygems.org"

gemspec

### ensure these gems are present in spec/dummy
gem 'jquery-rails'
gem 'jquery-ui-rails'
gem 'dynamic_form'
gem 'aasm'
gem 'sass'
gem 'rake', '< 11.0'
gem 'paper_trail', '~> 5.2.3'
###

### TravisCI db drivers
group :development, :test do
  gem 'gettext_i18n_rails', '~> 1.2.3'
  gem 'gettext', '>=3.0.2', :require => false, :group => :development
  gem 'mysql2', '~> 0.5.2'
  gem 'pg', '~> 0.18'
  gem 'rb-fsevent', require: false
  gem 'guard-rspec', require: false
  gem 'simplecov', require: false
  gem 'rails-dummy'#, github: 'wafcio/rails-dummy', branch: 'rails41'
  gem 'liquid'
  gem 'libxml-ruby'
  gem 'rails-controller-testing'
  if RUBY_VERSION =~ /^2/
    gem 'rubysl-rexml'
  end
  # gem 'pry'
  # gem 'pry-remote'
  # gem 'pry-stack_explorer'
  # gem 'pry-byebug'
end

gem 'database_cleaner'
