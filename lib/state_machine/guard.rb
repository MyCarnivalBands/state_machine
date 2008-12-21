require 'state_machine/eval_helpers'
require 'state_machine/assertions'

module StateMachine
  # Represents a set of requirements that must be met in order for a transition
  # or callback to occur.  Guards verify that the event, from state, and to
  # state of the transition match, in addition to if/unless conditionals for
  # an object's state.
  class Guard
    include Assertions
    include EvalHelpers
    
    # The transition/conditional options that must be met in order for the
    # guard to match
    attr_reader :requirements
    
    # A list of all of the states known to this guard.  This will pull state
    # values from the following requirements:
    # * +to+
    # * +from+
    # * +except_to+
    # * +except_from+
    attr_reader :known_states
    
    # Creates a new guard with the given requirements
    def initialize(requirements = {}) #:nodoc:
      assert_valid_keys(requirements, :to, :from, :on, :except_to, :except_from, :except_on, :if, :unless)
      
      @requirements = requirements
      @known_states = []
      
      # Normalize the requirements and track known states
      [:to, :from, :on, :except_to, :except_from, :except_on].each do |option|
        if @requirements.include?(option)
          values = @requirements[option]
          
          @requirements[option] = values = [values] unless values.is_a?(Array)
          @known_states |= values if [:to, :from, :except_to, :except_from].include?(option)
        end
      end
    end
    
    # Determines whether the given object / query matches the requirements
    # configured for this guard.  In addition to matching the event, from state,
    # and to state, this will also check whether the configured :if/:unless
    # conditionals pass on the given object.
    # 
    # Query options:
    # * +to+ - One or more states being transitioned to.  If none are specified, then this will always match.
    # * +from+ - One or more states being transitioned from.  If none are specified, then this will always match.
    # * +on+ - One or more events that fired the transition.  If none are specified, then this will always match.
    # * +except_to+ - One more states *not* being transitioned to
    # * +except_from+ - One or more states *not* being transitioned from
    # * +except_on+ - One or more events that *did not* fire the transition.
    # 
    # == Examples
    # 
    #   guard = StateMachine::Guard.new(:on => 'ignite', :from => [nil, 'parked'], :to => 'idling')
    #   
    #   # Successful
    #   guard.matches?(object, :on => 'ignite')                                      # => true
    #   guard.matches?(object, :from => nil)                                         # => true
    #   guard.matches?(object, :from => 'parked')                                    # => true
    #   guard.matches?(object, :to => 'idling')                                      # => true
    #   guard.matches?(object, :from => 'parked', :to => 'idling')                   # => true
    #   guard.matches?(object, :on => 'ignite', :from => 'parked', :to => 'idling')  # => true
    #   
    #   # Unsuccessful
    #   guard.matches?(object, :on => 'park')                                        # => false
    #   guard.matches?(object, :from => 'idling')                                    # => false
    #   guard.matches?(object, :to => 'first_gear')                                  # => false
    #   guard.matches?(object, :from => 'parked', :to => 'first_gear')               # => false
    #   guard.matches?(object, :on => 'park', :from => 'parked', :to => 'idling')    # => false
    def matches?(object, query = {})
      matches_query?(object, query) && matches_conditions?(object)
    end
    
    # Draws a representation of this guard on the given graph.  This will draw
    # an edge between every state this guard matches *from* to either the
    # configured to state or, if none specified, then a loopback to the from
    # state.
    # 
    # For example, if the following from states are configured:
    # * +first_gear+
    # * +idling+
    # * +backing_up+
    # 
    # ...and the to state is "parked", then the following edges will be created:
    # * +first_gear+  -> +parked+
    # * +idling+      -> +parked+
    # * +backing_up+  -> +parked+
    # 
    # Each edge will be labeled with the name of the event that would cause the
    # transition.
    # 
    # The collection of edges generated on the graph will be returned.
    def draw(graph, event_name, valid_states)
      # From states: :from, everything but :except states, or all states
      from_states = requirements[:from] || requirements[:except_from] && (valid_states - requirements[:except_from]) || valid_states
      
      # To state can be optional, otherwise it's a loopback
      if to_state = requirements[:to]
        to_state = State.id_for(to_state.first)
      end
      
      # Generate an edge between each from and to state
      from_states.collect do |from_state|
        from_state = State.id_for(from_state)
        graph.add_edge(from_state, to_state || from_state, :label => event_name)
      end
    end
    
    protected
      # Verify that the from state, to state, and event match the query
      def matches_query?(object, query)
        (!query || query.empty?) || [:from, :to, :on].all? do |option|
          !query.include?(option) || find_match(query[option], requirements[option], requirements[:"except_#{option}"])
        end
      end
      
      # Verify that the conditionals for this guard evaluate to true for the
      # given object
      def matches_conditions?(object)
        if requirements[:if]
          evaluate_method(object, requirements[:if])
        elsif requirements[:unless]
          !evaluate_method(object, requirements[:unless])
        else
          true
        end
      end
      
      # Attempts to find the given value in either a whitelist of values or
      # a blacklist of values.  The whitelist will always be used first if it
      # is specified.  If neither lists are specified, then this will always
      # find a match and return true.
      # 
      # == Examples
      # 
      #   find_match(nil, %w(parked idling), nil)             # => false
      #   find_match(nil, [nil], nil)                         # => true
      #   find_match('parked', nil, nil)                      # => true
      #   find_match('parked', %w(parked idling), nil)        # => true
      #   find_match('first_gear', %w(parked idling, nil)     # => false
      #   find_match('parked', nil, %w(parked idling))        # => false
      #   find_match('first_gear', nil, %w(parked idling))    # => true
      def find_match(value, whitelist, blacklist)
        if whitelist
          whitelist.include?(value)
        elsif blacklist
          !blacklist.include?(value)
        else
          true
        end
      end
  end
end
