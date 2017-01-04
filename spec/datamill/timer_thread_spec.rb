require 'spec_helper'

require 'datamill/timer_thread'

require 'thread'

describe Datamill::TimerThread do
  it "executes job when timeout is zero" do
    wait_for_condition do |guard|
      subject.delayed(0) do
        guard.notify
      end
    end
  end

  it "executes job when timeout is negative" do
    wait_for_condition do |guard|
      subject.delayed(-1000) do
        guard.notify
      end
    end
  end

  context "after an exception has occurred on a delayed block" do
    before do
      wait_for_condition do |guard|
        subject.delayed(-1000) do
          begin
            raise "exception"
          ensure
            guard.notify
          end
        end
      end
    end

    it "still operates another block" do
      wait_for_condition do |guard|
        subject.delayed(0) do
          guard.notify
        end
      end
    end
  end
end
