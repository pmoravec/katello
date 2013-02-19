#
# Copyright 2012 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'spec_helper'

describe Katello::Logging do
  let(:testing_config) do
    Katello::Configuration::Node.new(
        { :logging => { :colorize       => false,
                        :path           => '/var/log/katello',
                        :console_inline => false,
                        :log_trace      => false,
                        :loggers        => {
                            :root      => { :level    => 'info',
                                            :type     => 'file',
                                            :filename => 'test.log',
                                            :age      => 'weekly',
                                            :keep     => 1,
                                            :pattern  => "%m" },
                            :app       => { :level => 'debug' },
                            :sql       => { :level => 'warn' },
                            :tire_rest => { :enabled => false }
                        } },
        })
  end
  before { Katello.stub(:config => testing_config) }

  let(:logging) { Katello::Logging.new }

  describe "#configuration" do
    subject { logging.send :configuration }
    it { should respond_to(:colorize, :path, :console_inline, :loggers, :log_trace) }
  end

  describe "#root_configuration" do
    subject { logging.send :root_configuration }
    it { should respond_to(:level, :type) }
  end

  describe "#configure" do
    context "without Rails console session" do
      before { logging.configure }
      it "should not add stdout appender to root logger" do
        Logging.logger.root.appenders.should_not include(Logging.appenders.stdout)
      end

    end

    context "within Rails console session" do
      before do
        Rails::Console = 'defined'
        Katello.config.logging.stub(:console_inline => true)
        logging.should_receive(:configure_root_logger).once
        logging.should_receive(:configure_children_loggers).once
        logging.configure
      end

      it "should add stdout appender to root logger" do
        Logging.logger.root.appenders.should include(Logging.appenders.stdout)
      end
    end
  end

  describe "#configure_children_loggers" do
    # local helper
    def logger(name)
      Logging.logger[name]
    end

    before { logging.configure }

    it "should set correct levels" do
      logger('app').level.should eql(0)
      logger('sql').level.should eql(2)
      logger('tire_rest').level.should eql(1)
    end

    it "should unset additive flag only on disabled loggers" do
      logger('app').additive.should be_true
      logger('tire_rest').additive.should be_false
    end

    it "should not log trace" do
      logger('app').trace.should be_false
      logger('sql').trace.should be_false
      logger('tire_rest').trace.should be_false
    end

    context "log trace is enabled" do
      before do
        Katello.config.logging.stub(:log_trace => true)
        logging = Katello::Logging.new
        logging.configure
      end

      it "should configure log trace for all known loggers" do
        logger('app').trace.should be_true
        logger('sql').trace.should be_true
        logger('tire_rest').trace.should be_true
      end
    end
  end

  describe "#configure_root_logger(options)" do
    context "file appender is used" do
      before { logging.configure(:prefix => 'testing_') }
      it "should define one appender" do
        Logging.logger.root.appenders.size.should eql(1)
      end

      subject { Logging.logger.root.appenders.first }
      it { should be_kind_of(Logging::Appenders::RollingFile) }
      its(:name) { should eql('testing_joined') }
      after { Logging.logger.root.appenders = nil }
    end

    context "syslog appender is used" do
      before :all do
        Katello.config.logging.stub(:console_inline => false)
        Katello.config.logging.loggers.root.stub(:type => 'syslog')
        logging.configure(:prefix => 'testing_')
      end
      it "should define one appender" do
        Logging.logger.root.appenders.size.should eql(1)
      end

      subject { Logging.logger.root.appenders.first }
      it { should be_kind_of(Logging::Appenders::Syslog) }
      its(:name) { should eql('testing_joined') }
    end

    context "unsupported logger" do
      before do
        Katello.config.logging.loggers.root.stub(:type => 'nonsense')
      end
      it "should raise RuntimeError exception" do
        expect { logging.configure(:prefix => 'testing_') }.to raise_error(RuntimeError)
      end
    end
  end

  describe "#build_layout" do
    subject { logging.send :build_layout, '[%m]', true }
    it { should be_kind_of(Logging::Layouts::Pattern) }
    its(:pattern) { should eql('[%m]')}
    its(:color_scheme) { should be_present }

    context "without colors" do
      subject { logging.send :build_layout, '[%m]', false }
      its(:color_scheme) { should be_nil }
    end

    context "with log trace" do
      before { Katello.config.logging.stub(:log_trace => true) }
      subject { logging.send :build_layout, '[%m]', false }
      its(:pattern) { should match(/.*Log trace.*/)}
    end
  end

  describe "#configure_color_scheme" do
    subject { logging.send :configure_color_scheme }
    it { should be_kind_of(Logging::ColorScheme) }
  end

  describe "#default_path" do
    subject { logging.send :default_path }
    it { should be_kind_of(String) }
    it { should include(Rails.root.to_s) }
  end

  describe Katello::Logging::TireBridge do
    let(:logger) { mock("logger", :debug => true, :level => 0) }
    let(:bridge) { Katello::Logging::TireBridge.new(logger) }

    describe "#level" do
      subject { bridge.level }
      it { should eql('debug') }
    end

    describe "#write(message)" do
      before { logger.should_receive(:debug).once }
      subject { bridge.write('test') }
      it { should be_true }
    end
  end

end