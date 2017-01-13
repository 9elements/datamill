require 'datamill/identified_async_work'

require 'thread'

module Datamill

module HasAsyncWork
  # Utility glue around IdentifiedAsyncWork.
  # Usage:
  #
  # class Foo
  #   include HasAsyncWork
  #
  #   def self.setup # called before creating any instances
  #     # set up with a thread pool compatible with what `concurrent_ruby` offers.
  #     self.datamill_async_work_thread_pool = MyThreadPool.new
  #   end
  #
  #   def self.handle_async_work(work_id, param1, param2)
  #     # do something
  #   end
  #
  #   def foo(param1, param2)
  #     work_id = "some simple identifier, usually of course a dynamic value"
  #     async_work.for_id(work_id).call(param1, param2) unless async_work.for_id(work_id).running?
  #   end
  # end

  def self.included(other)
    other.extend ClassMethods
  end

  module ClassMethods
    attr_writer :datamill_async_work_thread_pool

    @mutex = Mutex.new
    class << self; attr_reader :mutex; end

    def datamill_async_work_thread_pool
      @datamill_async_work_thread_pool or raise("No thread pool configured")
    end

    def datamill_async_work_registry
      # This method is effectively used from the lifetime of an instance
      # of an including class. At that time, the thread pool must have been
      # initialized.

      return @datamill_async_work_registry if @datamill_async_work_registry

      ClassMethods.mutex.synchronize do
        @datamill_async_work_registry ||=
          IdentifiedAsyncWork.new(datamill_async_work_thread_pool) do |work_id, args|
            handle_async_work(work_id, *args)
          end
      end
    end

    def handle_async_work(work_id, *)
      raise NotImplementedError # you must implement this callback!
    end
  end

  private

  def async_work
    @async_work ||= AsyncWork.new(self.class.datamill_async_work_registry)
  end

  class AsyncWork
    def initialize(registry)
      @registry = registry
    end

    def for_id(work_id)
      AsyncWorkForId.new(@registry, work_id)
    end
  end

  class AsyncWorkForId
    def initialize(registry, work_id)
      @registry, @work_id = registry, work_id
    end

    def running?
      @registry.running?(@work_id)
    end

    def call(*args)
      @registry.run_asynchronously(@work_id, [@work_id, args])
      self
    end
  end
end

end
