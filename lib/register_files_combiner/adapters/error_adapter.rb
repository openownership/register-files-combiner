module RegisterFilesCombiner
  module Adapters
    class ErrorAdapter
      def error(_message)
        nil # TODO: Rollbar
      end
    end
  end
end
