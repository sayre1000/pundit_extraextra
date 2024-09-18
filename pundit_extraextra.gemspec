lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pundit_extraextra/version'

Gem::Specification.new do |s|
  s.name        = 'pundit_extraextra'
  s.version     = PunditExtraExtra::VERSION
  s.summary     = 'Additions for PunditExtra'
  s.description = 'Add CanCanCan like load and authorize to Pundit.'
  s.authors     = ['Danny Ben Shitrit', 'Andrew Michael Fahmy']
  s.email       = 'andrew.michael.fahmy@gmail.com'
  s.files       = Dir['README.md', 'lib/**/*.rb']
  s.homepage    = 'https://github.com/sayre1000/pundit_extraextra'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.0.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
