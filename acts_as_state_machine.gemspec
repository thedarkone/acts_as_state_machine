Gem::Specification.new do |s|
  s.name = 'tastebook-acts_as_state_machine'
  s.version = '3.0.2'
  s.date = '2013-03-26'

  s.summary = "Allows ActiveRecord models to define states and transition actions between them"
  s.description = "This act gives an Active Record model the ability to act as a finite state machine (FSM)."

  s.authors = ['RailsJedi', 'Scott Barron']
  s.email = 'ssinghi@kreeti.com'
  s.homepage = 'http://github.com/tastebook/acts_as_state_machine'

  s.has_rdoc = true
  s.rdoc_options = ["--main", "README"]
  s.extra_rdoc_files = ["README"]

  s.add_dependency 'activerecord', ['>= 3.1']
  s.require_paths     = ["lib"]

  s.files = ["CHANGELOG",
             "MIT-LICENSE",
             "README",
             "Rakefile",
             "TODO",
             "acts_as_state_machine.gemspec",
             "lib/acts_as_state_machine.rb"]

  s.test_files = ["test/fixtures",
                  "test/fixtures/conversations.yml",
                  "test/test_acts_as_state_machine.rb"]
end
