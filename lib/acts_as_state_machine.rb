module ScottBarron                   #:nodoc:
  module Acts                        #:nodoc:
    module StateMachine              #:nodoc:
      class InvalidState < Exception #:nodoc:
      end
      class NoInitialState < Exception #:nodoc:
      end

      def self.included(base)        #:nodoc:
        base.extend ActMacro
      end

      module SupportingClasses
        # Default transition action.  Always returns true.
        class State
          attr_reader :name, :value

          def initialize(name, options)
            @name  = name.to_sym
            @value = (options[:value] || @name).to_s
            @after = Array(options[:after])
            @enter = options[:enter]
            @exit  = options[:exit]
          end

          def entering(record, event, *args)
            record.send(:run_transition_action, @enter, event, *args)
          end

          def entered(record, event, *args)
            @after.each { |action| record.send(:run_transition_action, action, event, *args) }
          end

          def exited(record, event, *args)
            record.send(:run_transition_action, @exit, event, *args)
          end
        end

        class StateTransition
          attr_reader :from, :to, :opts, :event

          def initialize(options)
            @from  = options[:from].to_s
            @to    = options[:to].to_s
            @guard = options[:guard]
            @event = options[:event]
            @opts  = options
          end

          def guard(obj)
            @guard ? obj.send(:run_guard_action, @guard) : true
          end

          def perform(record, *args)
            return false unless guard(record)
            loopback = record.current_state.to_s == to
            states = record.class._states
            next_state = states[to]
            old_state = states[record.current_state.to_s]

            next_state.entering(record, event, *args) unless loopback

            record.update_attribute(record.class.state_column, next_state.value)

            record.send(:run_state_change_action, record.class.state_change_success_hook, next_state, event)

            next_state.entered(record, event, *args) unless loopback
            old_state.exited(record, event, *args) unless loopback
            true
          end

          def ==(obj)
            @from == obj.from && @to == obj.to
          end
        end

        class Event
          attr_reader :name
          attr_reader :transitions
          attr_reader :opts

          def initialize(name, opts, transition_table, &block)
            @name = name.to_sym
            @transitions = transition_table[@name] = []
            instance_eval(&block) if block
            @opts = opts
            @opts.freeze
            @transitions.freeze
            freeze
          end

          def next_states(record)
            @transitions.select { |t| t.from == record.current_state.to_s }
          end

          def fire(record, *args)
            transitioned = next_states(record).any? {|transition| transition.perform(record, *args) }
            unless transitioned
              record.send(:run_state_change_action, record.class.state_change_failure_hook, record.class._states[record.current_state.to_s], self)
            end
            transitioned
          end

          def transitions(trans_opts)
            Array(trans_opts[:from]).each do |s|
              @transitions << SupportingClasses::StateTransition.new(trans_opts.merge({:from => s.to_sym, :event => self}))
            end
          end
        end
      end

      module ActMacro
        # Configuration options are
        #
        # * +column+ - specifies the column name to use for keeping the state (default: state)
        # * +initial+ - specifies an initial state for newly created objects (required)
        def acts_as_state_machine(options = {})
          class_eval do
            extend ClassMethods
            include InstanceMethods

            raise NoInitialState unless options[:initial]

            class_attribute :_states
            self._states = {}

            class_attribute :initial_state
            self.initial_state = options[:initial]

            class_attribute :transition_table
            self.transition_table = {}

            class_attribute :event_table
            self.event_table = {}

            class_attribute :state_column
            self.state_column = options[:column] || 'state'

            class_attribute :state_change_success_hook
            self.state_change_success_hook = options[:success]

            class_attribute :state_change_failure_hook
            self.state_change_failure_hook = options[:failure]

            before_create :set_initial_state
            after_create  :run_initial_state_actions
          end
        end
      end

      module InstanceMethods
        def set_initial_state #:nodoc:
          write_attribute self.class.state_column, self.class.initial_state.to_s
        end

        def run_initial_state_actions
          initial = self.class._states[self.class.initial_state.to_s]
          initial.entering(self, nil)
          run_state_change_action(self.class.state_change_success_hook, initial, nil)
          initial.entered(self, nil)
        end

        # Returns the current state the object is in, as a Ruby symbol.
        def current_state
          self.send(self.class.state_column).to_sym
        end

        # Returns what the next state for a given event would be, as a Ruby symbol.
        def next_state_for_event(event)
          ns = next_states_for_event(event)
          ns.empty? ? nil : ns.first.to.to_sym
        end

        def next_states_for_event(event)
          self.class.transition_table[event.to_sym].select do |s|
            s.from == current_state.to_s
          end
        end

        private
        def run_guard_action(action)
          Symbol === action ? self.method(action).call : action.call(self) if action
        end

        def run_transition_action(action, event, *args)
          Symbol === action ? self.method(action).call(event, *args) : action.call(self, event, *args) if action
        end

        def run_state_change_action(action, state, event, *args)
          Symbol === action ? self.method(action).call(state, event, *args) : action.call(self, state, event, *args) if action
        end
      end

      module ClassMethods
        # Returns an array of all known states.
        def states
          _states.keys.collect { |state| state.to_sym }
        end

        # Define an event.  This takes a block which describes all valid transitions
        # for this event.
        #
        # Example:
        #
        # class Order < ActiveRecord::Base
        #   acts_as_state_machine :initial => :open
        #
        #   state :open
        #   state :closed
        #
        #   event :close_order do
        #     transitions :to => :closed, :from => :open
        #   end
        # end
        #
        # +transitions+ takes a hash where <tt>:to</tt> is the state to transition
        # to and <tt>:from</tt> is a state (or Array of states) from which this
        # event can be fired.
        #
        # This creates an instance method used for firing the event.  The method
        # created is the name of the event followed by an exclamation point (!).
        # Example: <tt>order.close_order!</tt>.
        def event(event, opts={}, &block)
          e = SupportingClasses::Event.new(event, opts, transition_table, &block)
          self.event_table = event_table.merge(event.to_sym => e)
          define_method("#{event.to_s}!") { |*args| raise InvalidState unless e.fire(self, *args) }
        end

        # Define a state of the system. +state+ can take an optional Proc object
        # which will be executed every time the system transitions into that
        # state.  The proc will be passed the current object.
        #
        # Example:
        #
        # class Order < ActiveRecord::Base
        #   acts_as_state_machine :initial => :open
        #
        #   state :open
        #   state :closed, Proc.new { |o| Mailer.send_notice(o) }
        # end
        def state(name, opts={})
          state = SupportingClasses::State.new(name, opts)
          self._states = _states.merge(state.value => state)

          define_method("#{state.name}?") { current_state.to_s == state.value }
        end

        # Wraps ActiveRecord::Base.find to conveniently find all records in
        # a given state.  Options:
        #
        # * +number+ - This is just :first or :all from ActiveRecord +find+
        # * +state+ - The state to find
        # * +args+ - The rest of the args are passed down to ActiveRecord +find+
        def find_in_state(number, state, *args)
          _state_scope(state).find(number, *args)
        end

        # Wraps ActiveRecord::Base.count to conveniently count all records in
        # a given state.  Options:
        #
        # * +state+ - The state to find
        # * +args+ - The rest of the args are passed down to ActiveRecord +find+
        def count_in_state(state, *args)
          _state_scope(state).count(*args)
        end

        # Wraps ActiveRecord::Base.calculate to conveniently calculate all records in
        # a given state.  Options:
        #
        # * +state+ - The state to find
        # * +args+ - The rest of the args are passed down to ActiveRecord +calculate+
        def calculate_in_state(state, *args)
          _state_scope(state).calculate(*args)
        end

        protected
        def _state_scope(state)
          raise InvalidState unless states.include?(state.to_sym)
          where(state_column => state.to_s)
        end
      end
    end
  end
end
