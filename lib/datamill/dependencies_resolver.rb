module Datamill

# Holds objects created by methods of a container object, while managing
# dependencies between these objects.
# Example:
#
#  class Container
#    def leaf
#      Leaf.new
#    end
#
#    def intermediate(leaf)
#      Intermediate.new(leaf)
#    end
#
#    def root(intermediate:)
#      Root.new(intermediate)
#    end
#  end
#
#  DependenciesResolver.new(Container.new).call(:root) # => Root instance returned by `root` method
#
# The resolver determines dependencies by looking at the names of method parameters in the container.
# The container can be any object, including one initialized with "deep" dependencies.
# The idea is that whilst source code must always linearize a dependency graph in textual form,
# at least the graph is easier to follow by simply looking at the `def` declarations.
class DependenciesResolver
  class FormalEntry
    def initialize(method)
      @method = method
    end

    def direct_dependencies
      @direct_dependencies ||=
        @method.parameters.each_with_object([]) do |pair, acc|
          kind, name = pair
          case kind
          when :req, :keyreq
            acc << name.to_sym
          when nil
          else
            raise "cannot handle param of unknown kind #{kind.inspect}"
          end
        end
    end

    def fill
      combined_args =
        @method.parameters.each_with_object([[], {}]) do |parameter, combined_args|
          kind, name = parameter
          value = yield(name)
          case kind
          when :req
            combined_args.first << value
          when :keyreq
            combined_args.last[name] = value
          end
        end
      direct, keyword_args = *combined_args

      if keyword_args.any?
        @method.call(*[*direct, keyword_args])
      else
        @method.call(*direct)
      end
    end
  end

  Error = Class.new(RuntimeError)
  UnknownEntry = Class.new(Error) do
    def initialize(name)
      @name = name
      @path = []
    end
    attr_accessor :path

    def to_s; message; end
    def message
      "Unknown container entry #{@name.inspect} (while resolving dependencies #{path.inspect})"
    end
  end
  CircularReference = Class.new(Error) do
    def initialize(cycles)
      @cycles = cycles
      super(message)
    end
    attr_reader :cycles

    def message
      "circular dependency/dependencies:\n#{
        cycles.map { |cycle| cycle.join " -> " }.join("\n")
      }"
    end
  end

  def initialize(container)
    @formal_entries = Hash.new do |hash, key|
      method =
        begin
          container.method(key)
        rescue NameError
          raise UnknownEntry.new(key)
        end
      hash[key] = FormalEntry.new(method)
    end

    @transitive_dependencies = Hash.new do |hash, key|
      hash[key] = calculate_transitive_deps(key, [])
    end

    @values = Hash.new do |hash, key|
      entry = @formal_entries[key]
      hash[key] = entry.fill do |name|
        @values[name]
      end
    end
  end

  def call(key)
    check_for_loops(key)
    @values[key.to_sym]
  end

  def calculate_transitive_deps(node, path)
    return @transitive_dependencies[node] if @transitive_dependencies.key?(node)

    begin
      direct_deps = @formal_entries[node].direct_dependencies
    rescue UnknownEntry => e
      if e.path.empty?
        e.path += path
        e.path << node
      end
      raise e
    end

    new_path = [*path, node]
    if (direct_deps & new_path).any?
      complain_about_loop(new_path, direct_deps)
    end

    result =
      direct_deps.map { |dep|
        calculate_transitive_deps(dep, new_path)
      }.reduce(direct_deps, :+)

    @transitive_dependencies[node] = result

    result
  end

  def check_for_loops(dep)
    @transitive_dependencies[dep.to_sym]
  end

  def complain_about_loop(path, direct_deps)
    cycles =
      (path & direct_deps).map { |seen_again|
        [
          *(path.drop_while { |node| node != seen_again }),
          seen_again
        ]
      }

    raise CircularReference.new(cycles)
  end
end

end
