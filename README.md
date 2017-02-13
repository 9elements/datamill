# Datamill

This gem implements a *reactor* processing events in a at-least-once delivery way.
Events are dispatched to singleton *handlers*, or they represent a message to a *cell*
handled by the cell's *behaviour*.

Cells are stateful entities identified by `id` and their behaviour's name.

Persistence for cell data and the reactor message queue is currently provided
by Redis.

## Architecture overview

### Persistent event queue, reactor and reactor handlers

```

+-----+
| app |--\                                       +---------+
+-----+  |                                    /->| handler |
         |                                    |  +---------+
+-----+  |   +-------------+     +---------+  |  +---------+
| app |--+->-| pers. queue |-->--| reactor |--+->| handler |
+-----+  |   +-------------+     +---------+  |  +---------+
         |                           ^        |  +---------+
+-----+  |                           |        \->| handler |
| app |--/               (injected messages)     +---------+
+-----+

```

You need to ensure that there is only one reactor at any time,
across all processes. Message producers ("app") can live in
various processes, but there must be only one reactor consuming
the queue.

Each message is delivered to each handler, inside the reactor process.
When the process terminates, processing will continue with the
last message that was not completely processed.

Apart from messages from the persistent queue, the reactor can
deliver messages injected from inside the reactor's process. There
is no guarantee that these messages will be handled (the process
may terminate).

### Cells and behaviours

```
                                             +-----------+
                                        /-<>-| behaviour |
                                        |    +-----------+
     +---------+  +-------------------+ |    +-----------+
-->--| reactor |--| (special handler) |-|-<>-| behaviour |
     +---------+  +-------------------+ |    +-----------+
                        ^               |    +-----------+
                        v               \-<>-| behaviour |
                    persistent storage       +-----------+
```

Each behaviour handles its own realm of cells. A cell is implemented
by its behaviour and has an id and some persistent data. The cells
of each behaviour are identified by their id. A behaviour's methods
are called inside the reactor's process.

Any code can send a message to a cell through the persistent queue.
From inside the process hosting the reactor, a non-persistent message
to a cell can be sent when persistence and delivery guarantees are
not desired. Messages to a cell are handled by a behaviour's
`handle_message` method.

A behaviour is also called on behalf of a cell in these situations:
* upon boot, when persistent data for the cell is found
* the cell has requested a timeout that has expired

Timeouts are non-persistent, a cell requiring a timeout has to
re-request one upon boot, should the process terminate too early.

All information needed by the behaviour to operate on behalf of a cell
is bundled in a `Datamill::Cell::State` object. The behaviour must
set attributes on this object for managing a cell's persistent data
and requesting a timeout for the cell.

The lifetime of a cell is directly bound to its persistent data.
A cell without persistent data is dead, unless a message for it has been
send which is handled by the behaviour's `handle_message` method.
The cell dies right away unless the behaviour sets persistent data for
it.  A dead cell consumes no resources. A behaviour must clear a cell's
persistent data as soon as possible.

This means these transitions are possible:

```
 dead or alive -> handling a message                      -> dead or alive
         alive -> handling a timeout or boot notification -> dead or alive
```

If needed, a behaviour must implement migrating
persistent data from previous versions.

### Cell cultures and cell runs

Behaviours implement a cell by managing the cell's state, which
encapsulates all the state of the cell and contains no behaviour
of itself. This is a rather functional approach and not always
nice to operate with. To give this a more object-oriented flavour,
you can implement a *cell culture* using `Datamill::Cell::Behaviour`.
This will provide the behaviour, the interface toward the reactor, for
you. Inside the cell culture you describe what a *cell run* looks like,
a class instantiated by the behaviour to handle a single invocation
for the cell. On this cell run you can implement general handling
around all method calls (like logging, exception handling,
presenting a cell's id in a more suitable way...) as well as respond
to cell messages.

## Example

TBD

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'datamill'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install datamill

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/datamill. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

