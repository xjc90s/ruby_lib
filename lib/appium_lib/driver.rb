# frozen_string_literal: true

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Load only Minitest is loaded
if defined?(Minitest::VERSION)
  # Fix uninitialized constant Minitest (NameError)
  module Minitest
    # Fix superclass mismatch for class Spec
    class Runnable
    end

    begin
      class Test < Runnable
      end
    rescue TypeError => te
      # http://docs.seattlerb.org/minitest/History_rdoc.html#label-5.11.0+-2F+2018-01-01
      # for 5.11.0/5.11.1
      # `Minitest::Test` became a subclass of `Minitest::Result`
      raise TypeError, te.message unless te.message == 'superclass mismatch for class Test'

      class Test < Result
      end
    end
  end
end

require 'appium_lib_core'
require 'uri'

module Appium
  class Driver
    # @private
    class << self
      def convert_to_symbol(value)
        if value.nil?
          value
        else
          value.to_sym
        end
      end

      # @private
      def get_cap(caps, name)
        name_with_prefix = "#{::Appium::Core::Base::Bridge::APPIUM_PREFIX}#{name}"
        caps[convert_to_symbol name] ||
          caps[name] ||
          caps[convert_to_symbol name_with_prefix] ||
          caps[name_with_prefix]
      end
    end

    # attr readers are promoted to global scope. To avoid clobbering, they're
    # made available via the driver_attributes method
    #
    # attr_accessor is repeated for each one so YARD documents them properly.

    # The amount to sleep in seconds before every webdriver http call.
    attr_accessor :global_webdriver_http_sleep

    # SauceLab's settings
    attr_reader :sauce
    # Username for use on Sauce Labs. Set `false` to disable Sauce, even when SAUCE_USERNAME is in ENV.
    # same as @sauce.username
    attr_reader :sauce_username
    # Access Key for use on Sauce Labs. Set `false` to disable Sauce, even when SAUCE_ACCESS_KEY is in ENV.
    # same as @sauce.access_key
    attr_reader :sauce_access_key
    # Override the Sauce Appium endpoint to allow e.g. TestObject tests
    # same as @sauce.endpoint
    attr_reader :sauce_endpoint

    # from Core
    # read http://www.rubydoc.info/github/appium/ruby_lib_core/Appium/Core/Driver
    attr_reader :caps
    attr_reader :custom_url
    attr_reader :default_wait
    attr_reader :appium_port
    attr_reader :appium_device
    attr_reader :automation_name
    attr_reader :listener
    attr_reader :http_client
    attr_reader :appium_wait_timeout
    attr_reader :appium_wait_interval

    # Appium's server version
    attr_reader :appium_server_status
    # Boolean debug mode for the Appium Ruby bindings
    attr_reader :appium_debug
    # Returns the driver
    # @return [Driver] the driver
    attr_reader :driver
    # Instance of Appium::Core::Driver
    attr_reader :core

    # Creates a new driver. The driver is defined as global scope by default.
    # We can avoid defining global driver.
    #
    # @example
    #
    #   require 'rubygems'
    #   require 'appium_lib'
    #
    #   # platformName takes a string or a symbol.
    #   # Start iOS driver with global scope
    #   opts = {
    #            caps: {
    #              platformName: :ios,
    #              app: '/path/to/MyiOS.app'
    #            },
    #            appium_lib: {
    #              server_url: 'http://127.0.0.1:4723'
    #              wait_timeout: 30
    #            }
    #          }
    #   appium_driver = Appium::Driver.new(opts, true)
    #   appium_driver.start_driver
    #
    #   # Start Android driver with global scope
    #   opts = {
    #            caps: {
    #              platformName: :android,
    #              app: '/path/to/my.apk'
    #            },
    #            appium_lib: {
    #              wait_timeout: 30,
    #              wait_interval: 1
    #            }
    #          }
    #   appium_driver = Appium::Driver.new(opts, true)
    #   appium_driver.start_driver
    #
    #   # Start iOS driver without global scope
    #   opts = {
    #            caps: {
    #              platformName: :ios,
    #              app: '/path/to/MyiOS.app'
    #            },
    #            appium_lib: {
    #              wait_timeout: 30
    #            }
    #          }
    #   appium_driver = Appium::Driver.new(opts, false)
    #   appium_driver.start_driver
    #
    #   # Start iOS driver without global scope
    #   opts = {
    #            caps: {
    #              platformName: :ios,
    #              app: '/path/to/MyiOS.app'
    #            },
    #            appium_lib: {
    #              wait_timeout: 30
    #            },
    #            global_driver: false
    #          }
    #   appium_driver = Appium::Driver.new(opts)
    #   appium_driver.start_driver
    #
    # @param opts [Object] A hash containing various options.
    # @param global_driver [Bool] A bool require global driver before initialize.
    # @return [Driver]
    def initialize(opts = {}, global_driver = false)
      # Capybara can't put `global_driver` as the 2nd argument.
      global_driver = opts.delete :global_driver if global_driver.nil?

      $driver&.driver_quit if global_driver

      raise ArgumentError, 'opts must be a hash' unless opts.is_a? Hash

      @core = ::Appium::Core.for(opts)
      extend ::Appium::Core::Device

      opts = Appium.symbolize_keys opts
      appium_lib_opts = opts[:appium_lib] || {}

      @caps = @core.caps
      @custom_url = @core.custom_url
      @default_wait = @core.default_wait || 0
      @appium_port = @core.port
      @appium_wait_timeout = @core.wait_timeout
      @appium_wait_interval = @core.wait_interval
      @listener = @core.listener
      @appium_device = @core.device
      @automation_name = @core.automation_name

      # Arrange the app capability. This must be after @core = ::Appium::Core.for(opts)
      set_app_path(opts)

      # enable debug patch
      @appium_debug = appium_lib_opts.fetch :debug, !!defined?(Pry) # rubocop:disable Style/DoubleNegation
      set_sauce_related_values(appium_lib_opts)

      # Extend Common methods
      extend Appium::Common
      extend Appium::Device

      # Extend each driver's methods
      extend_for(device: @core.device, automation_name: @core.automation_name)

      # for command

      if @appium_debug
        Appium::Logger.debug opts unless opts.empty?
        Appium::Logger.debug "Debug is: #{@appium_debug}"
        Appium::Logger.debug "Device is: #{@core.device}"
      end

      # Save global reference to last created Appium driver for top level methods.
      $driver = self if global_driver

      self # rubocop:disable Lint/Void # return newly created driver
    end

    private

    # @private
    def extend_for(device:, automation_name:)
      case device
      when :android
        case automation_name
        when :uiautomator2
          ::Appium::Android::Uiautomator2::Bridge.for(self)
        when :espresso
          ::Appium::Android::Espresso::Bridge.for(self)
        else # default and UiAutomator
          ::Appium::Android::Bridge.for(self)
        end
      when :ios, :tvos
        # default and XCUITest
        ::Appium::Ios::Xcuitest::Bridge.for(self)
      when :mac
        # no Mac specific extentions
        Appium::Logger.debug('mac')
      when :windows
        # no windows specific extentions
        Appium::Logger.debug('windows')
      when :tizen
        # https://github.com/Samsung/appium-tizen-driver
        Appium::Logger.debug('tizen')
      when :youiengine
        # https://github.com/YOU-i-Labs/appium-youiengine-driver
        Appium::Logger.debug('YouiEngine')
      else
        case automation_name
        when :youiengine
          # https://github.com/YOU-i-Labs/appium-youiengine-driver
          Appium::Logger.debug('YouiEngine')
        else
          Appium::Logger.debug('no device matched') # core also shows warning message
        end
      end
    end

    # @private
    # Deprecated. TODO: remove
    def set_app_path(opts)
      return unless @core.caps

      # return the path exists on the local
      app_path = Driver.get_cap(@core.caps, 'app')
      return if app_path.nil?
      return if File.exist?(app_path)

      @core.caps['app'] = self.class.absolute_app_path opts
    end

    # @private
    def set_sauce_related_values(appium_lib_opts)
      @sauce = Appium::SauceLabs.new(appium_lib_opts)
      @sauce_username   = @sauce.username
      @sauce_access_key = @sauce.access_key
      @sauce_endpoint   = @sauce.endpoint
    end

    public

    # Returns a hash of the driver attributes
    def driver_attributes
      {
        caps:                @core.caps,
        automation_name:     @core.automation_name,
        custom_url:          @core.custom_url,
        default_wait:        @default_wait,
        sauce_username:      @sauce.username,
        sauce_access_key:    @sauce.access_key,
        sauce_endpoint:      @sauce.endpoint,
        port:                @core.port,
        device:              @core.device,
        debug:               @appium_debug,
        listener:            @listener,
        wait_timeout:        @core.wait_timeout,
        wait_interval:       @core.wait_interval
      }
    end

    def device_is_android?
      @core.device == :android
    end

    def device_is_ios?
      @core.device == :ios
    end

    def device_is_windows?
      @core.device == :windows
    end

    # Return true if automationName is 'uiautomator2'
    # @return [Boolean]
    def automation_name_is_uiautomator2?
      !@core.automation_name.nil? && @core.automation_name == :uiautomator2
    end

    # Return true if automationName is 'Espresso'
    # @return [Boolean]
    def automation_name_is_espresso?
      !@core.automation_name.nil? && @core.automation_name == :espresso
    end

    # Return true if automationName is 'XCUITest'
    # @return [Boolean]
    def automation_name_is_xcuitest?
      !@core.automation_name.nil? && @core.automation_name == :xcuitest
    end

    # An entry point to chain W3C actions
    # Read https://www.rubydoc.info/github/appium/ruby_lib_core/Appium/Core/Base/Bridge/W3C#action-instance_method
    #
    # @return [Selenium::WebDriver::PointerActions]
    #
    # @example
    #
    #     element = find_element(:id, "some id")
    #     action.click(element).perform # The `click` is a part of `PointerActions`
    #
    def action
      @driver&.action
    end

    # Returns the server's version info
    #
    # @example
    #   {
    #     "build" => {
    #         "version" => "0.18.1",
    #         "revision" => "d242ebcfd92046a974347ccc3a28f0e898595198"
    #     }
    #   }
    #
    # @return [Hash]
    def appium_server_version
      @core.appium_server_version
    rescue Selenium::WebDriver::Error::WebDriverError => ex
      raise ::Appium::Core::Error::ServerError unless ex.message.include?('content-type=""')

      # server (TestObject for instance) does not respond to status call
      {}
    end
    alias remote_status appium_server_version

    # Return the platform version as an array of integers
    # @return [Array<Integer>]
    def platform_version
      return [] if @driver.nil?

      p_version = @driver.capabilities['platformVersion']
      p_version.split('.').map(&:to_i)
    end

    # Returns the client's version info
    #
    # @example
    #
    #   {
    #       "version" => "9.1.1"
    #   }
    #
    # @return [Hash]
    def appium_client_version
      { version: ::Appium::VERSION }
    end

    # [Deprecated] Converts app_path to an absolute path.
    #
    # opts is the full options hash (caps and appium_lib). If server_url is set
    # then the app path is used as is.
    #
    # if app isn't set then an error is raised.
    #
    # @return [String] APP_PATH as an absolute path
    def self.absolute_app_path(opts)
      raise ArgumentError, 'opts must be a hash' unless opts.is_a? Hash

      caps = opts[:caps] || opts['caps'] || {}
      app_path = get_cap(caps, 'app')
      raise ArgumentError, 'absolute_app_path invoked and app is not set!' if app_path.nil? || app_path.empty?
      # Sauce storage API. http://saucelabs.com/docs/rest#storage
      return app_path if app_path.start_with? 'sauce-storage:'
      return app_path if app_path =~ URI::DEFAULT_PARSER.make_regexp # public URL for Sauce

      ::Appium::Logger.warn('[Deprecation] Converting the path to absolute path will be removed. ' \
                            'Please specify the full path which can be accessible from the appium server')

      absolute_app_path = File.expand_path app_path
      if File.exist? absolute_app_path
        absolute_app_path
      else
        ::Appium::Logger.info("Use #{app_path}")
        app_path
      end
    end

    # Get the server url
    # @return [String] the server url
    def server_url
      return @core.custom_url if @core.custom_url
      return @sauce.server_url if @sauce.sauce_server_url?

      "http://127.0.0.1:#{@core.port}"
    end

    # Restarts the driver
    # @return [Driver] the driver
    def restart
      driver_quit
      start_driver
    end

    # Takes a png screenshot and saves to the target path.
    #
    # @example
    #
    #   screenshot '/tmp/hi.png'
    #
    # @param png_save_path [String] the full path to save the png
    # @return [File]
    def screenshot(png_save_path)
      @driver&.save_screenshot png_save_path
    end

    # Takes a png screenshot of particular element's area
    #
    # @example
    #
    #   el = find_element :accessibility_id, zzz
    #   element_screenshot el, '/tmp/hi.png'
    #
    # @param [String] element Element take a screenshot
    # @param [String] png_save_path the full path to save the png
    # @return [File]
    def element_screenshot(element, png_save_path)
      @driver&.take_element_screenshot element, png_save_path
      nil
    end

    # Quits the driver
    # @return [void]
    def driver_quit
      @driver&.quit
      @driver = nil
    rescue Selenium::WebDriver::Error::WebDriverError
      nil
    end
    alias quit_driver driver_quit

    # Get the device window's size.
    # @return [Selenium::WebDriver::Dimension]
    #
    # @example
    #
    #   size = @driver.window_size
    #   size.width #=> Integer
    #   size.height #=> Integer
    #
    def window_size
      # maybe exception is expected as no driver created
      raise NoDriverInstanceError if @driver.nil?

      @driver.window_size
    end

    # Get the device window's rect.
    # @return [Selenium::WebDriver::Rectangle]
    #
    # @example
    #
    #   size = @driver.window_size
    #   size.width #=> Integer
    #   size.height #=> Integer
    #   size.x #=> Integer
    #   size.y #=> Integer
    #
    def window_rect
      raise NoDriverInstanceError if @driver.nil?

      @driver.window_rect
    end

    # Creates a new global driver and quits the old one if it exists.
    # You can customise http_client as the following
    #
    # Read http://www.rubydoc.info/github/appium/ruby_lib_core/Appium/Core/Device to understand more what the driver
    # can call instance methods.
    #
    # @example
    #
    #   require 'rubygems'
    #   require 'appium_lib'
    #
    #   # platformName takes a string or a symbol.
    #   # Start iOS driver
    #   opts = {
    #            caps: {
    #              platformName: :ios,
    #              app: '/path/to/MyiOS.app'
    #            },
    #            appium_lib: {
    #              wait_timeout: 30
    #            }
    #          }
    #   appium_driver = Appium::Driver.new(opts) #=> return an Appium::Driver instance
    #   appium_driver.start_driver #=> return an Appium::Core::Base::Driver
    #
    # @option http_client_ops [Hash] :http_client Custom HTTP Client
    # @option http_client_ops [Hash] :open_timeout Custom open timeout for http client.
    # @option http_client_ops [Hash] :read_timeout Custom read timeout for http client.
    # @return [Selenium::WebDriver] the new global driver
    def start_driver(http_client_ops = { http_client: nil, open_timeout: 999_999, read_timeout: 999_999 })
      if http_client_ops[:http_client].nil?
        http_client = ::Appium::Http::Default.new(open_timeout: http_client_ops[:open_timeout],
                                                  read_timeout: http_client_ops[:read_timeout])
      end

      # TODO: do not kill the previous session in the future version.
      if $driver.nil?
        driver_quit
      else
        $driver.driver_quit
      end

      # If automationName is set only in server side, then the following automation_name should be nil before
      # starting driver.
      automation_name = @core.automation_name

      @driver = @core.start_driver(server_url: server_url,
                                   http_client_ops: {
                                     http_client: http_client,
                                     open_timeout: 999_999,
                                     read_timeout: 999_999
                                   })
      @http_client = @core.http_client

      # if automation_name was nil before start_driver, then re-extend driver specific methods
      # to be able to extend correctly.
      extend_for(device: @core.device, automation_name: @core.automation_name) if automation_name.nil?

      @appium_server_status = appium_server_version

      @driver
    end

    # To ignore error for Espresso Driver
    def set_implicit_wait(wait)
      @driver.manage.timeouts.implicit_wait = wait
    rescue Selenium::WebDriver::Error::UnknownError => e
      unless e.message.include?('The operation requested is not yet implemented by Espresso driver')
        raise ::Appium::Core::Error::ServerError
      end

      {}
    end

    # Set implicit wait to zero.
    def no_wait
      @driver&.manage&.timeouts&.implicit_wait = 0
    end

    # Set implicit wait. Default to @default_wait.
    #
    # @example
    #
    #   set_wait 2
    #   set_wait # @default_wait
    #
    #
    # @param timeout [Integer] the timeout in seconds
    # @return [void]
    def set_wait(timeout = nil)
      timeout = @default_wait if timeout.nil?
      @driver&.manage&.timeouts&.implicit_wait = timeout
    end

    # Returns existence of element.
    #
    # Example:
    #
    # exists { button('sign in') } ? puts('true') : puts('false')
    #
    # @param [Integer] pre_check The amount in seconds to set the
    #                             wait to before checking existence
    # @param [Integer] post_check The amount in seconds to set the
    #                             wait to after checking existence
    # @yield The block to call
    # @return [Boolean]
    def exists(pre_check = 0, post_check = @default_wait)
      # do not uset set_wait here.
      # it will cause problems with other methods reading the default_wait of 0
      # which then gets converted to a 1 second wait.
      @driver&.manage&.timeouts&.implicit_wait = pre_check
      # the element exists unless an error is raised.
      exists = true

      begin
        yield # search for element
      rescue StandardError
        exists = false # error means it's not there
      end

      # restore wait
      @driver&.manage&.timeouts&.implicit_wait = post_check if post_check != pre_check

      exists
    end

    # The same as @driver.execute_script
    # @param [String] script The script to execute
    # @param [*args] args The args to pass to the script
    # @return [Object]
    def execute_script(script, *args)
      raise NoDriverInstanceError if @driver.nil?

      @driver.execute_script script, *args
    end

    ###
    # Wrap calling selenium webdrier APIs via ruby_core
    ###
    # Get the window handles of open browser windows
    def execute_async_script(script, *args)
      raise NoDriverInstanceError if @driver.nil?

      @driver.execute_async_script script, *args
    end

    # Run a set of script against the current session, allowing execution of many commands in one Appium request.
    # Supports {https://webdriver.io/docs/api.html WebdriverIO} API so far.
    # Please read {http://appium.io/docs/en/commands/session/execute-driver command API} for more details
    # about acceptable scripts and the output.
    #
    # @param [String] script The string consisting of the script itself
    # @param [String] type The name of the script type.
    #                      Defaults to 'webdriverio'. Depends on server implementation which type is supported.
    # @param [Integer] timeout_ms The number of `ms` Appium should wait for the script to finish
    #                          before killing it due to timeout.
    #
    # @return [Appium::Core::Base::Device::ExecuteDriver::Result] The script result parsed by
    #                          Appium::Core::Base::Device::ExecuteDriver::Result.
    #
    # @raise [::Selenium::WebDriver::Error::UnknownError] If something error happens in the script.
    #                                                     It has the original message.
    #
    # @example
    #      script = <<~SCRIPT
    #        const status = await driver.status();
    #        console.warn('warning message');
    #        return [status];
    #      SCRIPT
    #      r = @@driver.execute_driver(script: script, type: 'webdriverio', timeout: 10_000)
    #      r        #=> An instance of Appium::Core::Base::Device::ExecuteDriver::Result
    #      r.result #=> The `result` key part as the result of the script
    #      r.logs   #=> The `logs` key part as `{'log' => [], 'warn' => [], 'error' => []}`
    #
    def execute_driver(script: '', type: 'webdriverio', timeout_ms: nil)
      raise NoDriverInstanceError if @driver.nil?

      @driver.execute_driver(script: script, type: type, timeout_ms: timeout_ms)
    end

    def window_handles
      raise NoDriverInstanceError if @driver.nil?

      @driver.window_handles
    end

    # Get the current window handle
    def window_handle
      raise NoDriverInstanceError if @driver.nil?

      @driver.window_handle
    end

    def navigate
      raise NoDriverInstanceError if @driver.nil?

      @driver.navigate
    end

    def manage
      raise NoDriverInstanceError if @driver.nil?

      @driver.manage
    end

    def get(url)
      raise NoDriverInstanceError if @driver.nil?

      @driver.get(url)
    end

    def current_url
      raise NoDriverInstanceError if @driver.nil?

      @driver.current_url
    end

    def title
      raise NoDriverInstanceError if @driver.nil?

      @driver.title
    end

    # @return [TargetLocator]
    # @see TargetLocator
    def switch_to
      raise NoDriverInstanceError if @driver.nil?

      @driver.switch_to
    end
    ###
    # End core
    ###

    # Calls @driver.find_elements_with_appium
    #
    # @example
    #
    #   @driver = Appium::Driver.new(opts, false)
    #   @driver.start_driver
    #   @driver.find_elements :predicate, yyy
    #
    # If you call `Appium.promote_appium_methods`, you can call `find_elements` directly.
    #
    # @example
    #
    #   @driver = Appium::Driver.new(opts, false)
    #   @driver.start_driver
    #   @driver.find_elements :predicate, yyy
    #
    # If you call `Appium.promote_appium_methods`, you can call `find_elements` directly.
    #
    # @param [*args] args The args to use
    # @return [Array<Element>] Array is empty when no elements are found.
    def find_elements(*args)
      raise NoDriverInstanceError if @driver.nil?

      @driver.find_elements(*args)
    end

    # Calls @driver.find_element
    #
    # @example
    #
    #   @driver = Appium::Driver.new(opts, false)
    #   @driver.start_driver
    #   @driver.find_element :accessibility_id, zzz
    #
    # If you call `Appium.promote_appium_methods`, you can call `find_element` directly.
    #
    # @param [*args] args The args to use
    # @return [Element]
    def find_element(*args)
      raise NoDriverInstanceError if @driver.nil?

      @driver.find_element(*args)
    end

    # Return ImageElement if current view has a partial image
    #
    # @param [String] png_img_path A path to a partial image you'd like to find
    #
    # @return [::Appium::Core::ImageElement]
    # @raise [::Appium::Core::Error::NoSuchElementError|::Appium::Core::Error::CoreError] No such element
    #
    # @example
    #
    #     @driver.find_element_by_image './test/functional/data/test_element_image.png'
    #
    def find_element_by_image(png_img_path)
      raise NoDriverInstanceError if @driver.nil?

      @driver.find_element_by_image(png_img_path)
    end

    # Return ImageElement if current view has partial images
    #
    # @param [[String]] png_img_paths Paths to a partial image you'd like to find
    #
    # @return [[::Appium::Core::ImageElement]]
    # @return [::Appium::Core::Error::CoreError]
    #
    # @example
    #
    #     @driver.find_elements_by_image ['./test/functional/data/test_element_image.png']
    #
    def find_elements_by_image(png_img_paths)
      raise NoDriverInstanceError if @driver.nil?

      @driver.find_elements_by_image(png_img_paths)
    end

    # Calls @driver.set_location
    #
    # @note This method does not work on real devices.
    #
    # @param  [Hash] opts consisting of:
    # @option opts [Float] :latitude the latitude in degrees (required)
    # @option opts [Float] :longitude the longitude in degees (required)
    # @option opts [Float] :altitude the altitude, defaulting to 75
    # @return [Selenium::WebDriver::Location] the location constructed by the selenium webdriver
    def set_location(opts = {})
      raise NoDriverInstanceError if @driver.nil?

      latitude = opts.fetch(:latitude)
      longitude = opts.fetch(:longitude)
      altitude = opts.fetch(:altitude, 75)
      @driver.set_location(latitude, longitude, altitude)
    end

    # @since Appium 1.16.0
    #
    # Logs a custom event. The event is available via {::Appium::Core::Events#get}.
    #
    # @param [String] vendor The vendor prefix for the event
    # @param [String] event The name of event
    # @return [nil]
    #
    # @example
    #
    #   log_event vendor: 'appium', event: 'funEvent'
    #
    #   log_event = { vendor: 'appium', event: 'anotherEvent' }
    #   log_events #=> {...., 'appium:funEvent' => [1572957315, 1572960305],
    #              #          'appium:anotherEvent' => 1572959315}
    #
    def log_event(vendor:, event:)
      raise NoDriverInstanceError if @driver.nil?

      @driver.logs.event vendor: vendor, event: event
    end

    def log_event=(log_event)
      raise if @driver.nil?
      unless log_event.is_a?(Hash)
        raise ::Appium::Core::Error::ArgumentError('log_event should be Hash like { vendor: "appium", event: "funEvent"}')
      end

      @driver.logs.event vendor: log_event[:vendor], event: log_event[:event]
    end

    # @since Appium 1.16.0
    # Returns events with filtering with 'type'. Defaults to all available events.
    #
    # @param [String] type The type of events to get
    # @return [Hash]
    #
    # @example
    #
    #   log_events #=> {}
    #   log_events #=> {'commands' => [{'cmd' => 123455, ....}], 'startTime' => 1572954894127, }
    #
    def log_events(type = nil)
      raise NoDriverInstanceError if @driver.nil?

      @driver.logs.events(type)
    end

    # Quit the driver and Pry.
    # quit and exit are reserved by Pry.
    # @return [void]
    def x
      driver_quit
      exit # exit pry
    end
  end # class Driver
end # module Appium
