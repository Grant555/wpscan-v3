require 'spec_helper'

describe WPScan::Controller::Core do
  subject(:core)       { described_class.new }
  let(:target_url)     { 'http://ex.lo/' }
  let(:parsed_options) { { url: target_url } }

  before do
    WPScan::Browser.reset
    described_class.parsed_options = parsed_options
  end

  describe '#cli_options' do
    its(:cli_options) { should_not be_empty }
    its(:cli_options) { should be_a Array }

    it 'contains to correct options' do
      cli_options = core.cli_options
      expect(cli_options.map(&:to_sym)).to include(:url, :server, :force, :update)

      # Ensures the :url is the first one and is correctly setup
      expect(cli_options.first.to_sym).to eql :url
      expect(cli_options.first.required_unless).to eql [:update]
    end
  end

  describe '#load_server_module' do
    after do
      expect(core.target).to receive(:server).and_return(@stubbed_server)
      expect(core.load_server_module).to eql @expected

      [core.target, WPScan::WpItem.new(target_url, core.target)].each do |instance|
        expect(instance).to respond_to(:directory_listing?)
        expect(instance).to respond_to(:directory_listing_entries)

        # The below doesn't work, the module would have to be removed from the class
        # TODO: find a way to test this
        # expect(instance.server).to eql @expected if instance.is_a? WPScan::WpItem
      end
    end

    context 'when no --server supplied' do
      [:Apache, :IIS, :Nginx].each do |server|
        it "loads the #{server} module and returns :#{server}" do
          @stubbed_server = server
          @expected       = server
        end
      end
    end

    context 'when --server' do
      [:apache, :iis, :nginx].each do |server|
        context "when #{server}" do
          let(:parsed_options) { super().merge(server: server) }

          it "loads the #{server.capitalize} module and returns :#{server}" do
            @stubbed_server = [:Apache, nil, :IIS, :Nginx].sample
            @expected       = server == :iis ? :IIS : server.to_s.camelize.to_sym
          end
        end
      end
    end
  end

  describe '#before_scan' do
    before do
      stub_request(:get, target_url)

      expect(core.formatter).to receive(:output).with('banner', hash_including(verbose: nil), 'core')

      unless parsed_options[:update]
        expect_any_instance_of(WPScan::DB::Updater).to receive(:missing_files?).and_return(false)
      end

      unless defined?(redirection)
        expect(core).to receive(:load_server_module)
        expect(core.target).to receive(:wordpress?).and_return(wordpress?)
      end
    end

    # TODO: add the case when --url is not supplied
    context 'when --update' do
      let(:wordpress?)     { true }
      let(:parsed_options) { super().merge(update: true) }

      it 'calls the formatter when started and finished and update the db' do
        expect(core.formatter).to receive(:output)
          .with('db_update_started', hash_including(verbose: nil), 'core').ordered

        expect_any_instance_of(WPScan::DB::Updater).to receive(:update)

        expect(core.formatter).to receive(:output)
          .with('db_update_finished', hash_including(verbose: nil), 'core').ordered

        expect { core.before_scan }.to_not raise_error
      end
    end

    context 'when a redirect occurs' do
      before { expect(core.target).to receive(:redirection).and_return(redirection) }

      context 'to the wp-admin/install.php' do
        let(:redirection) { "#{target_url}wp-admin/install.php" }

        it 'calls the formatter with the correct parameters and exit' do
          expect(core.formatter).to receive(:output)
            .with('not_fully_configured', hash_including(url: redirection), 'core').ordered

          expect { core.before_scan }.to raise_error(SystemExit)
        end
      end

      context 'to something else' do
        let(:redirection) { 'http://g.com/' }

        it 'raises an error' do
          expect { core.before_scan }.to raise_error(CMSScanner::HTTPRedirectError)
        end
      end

      context 'to another path with the wp-admin/install.php in the query' do
        let(:redirection) { "#{target_url}index.php?a=/wp-admin/install.php" }

        it 'raises a error' do
          expect { core.before_scan }.to raise_error(CMSScanner::HTTPRedirectError)
        end
      end
    end

    context 'when wordpress' do
      let(:wordpress?) { true }

      it 'does not raise any error' do
        expect { core.before_scan }.to_not raise_error
      end
    end

    context 'when not wordpress' do
      let(:wordpress?) { false }

      context 'when no --force' do
        it 'raises an error' do
          expect { core.before_scan }.to raise_error(WPScan::NotWordPressError)
        end
      end

      context 'when --force' do
        let(:parsed_options) { super().merge(force: true) }

        it 'does not raise any error' do
          expect { core.before_scan }.to_not raise_error
        end
      end
    end
  end
end