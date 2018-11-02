$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "pg/histogram/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "pg-histogram"
  s.version     = Pg::Histogram::VERSION
  s.authors     = ["Mark Borkum"]
  s.email       = ["mark.borkum@pnnl.gov"]
  s.homepage    = "https://github.com/pnnl/pg-histogram"
  s.summary     = "PostgreSQL histograms for ActiveRecord relations"
  s.description = "PostgreSQL histograms for ActiveRecord relations"
  s.license     = "BSD-3-Clause"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.2.1"
  s.add_dependency "pg"
end
