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

require_relative '../../lib/appium_lib'

def des_server_caps
  {
    debug: true,
    server_url: ENV['appium_server'] ||= 'http://127.0.0.1:4723',
    wait: 25,
    wait_timeout: 20,
    wait_interval: 0.3
  }
end

class TestParallelRunThread
  def initialize(capability)
    @capability = capability
  end

  def setup
    @appium = Appium::Driver.new({ caps: @capability, appium_lib: des_server_caps }, false)
    @appium.start_driver
  end

  def teardown
    @appium.quit_driver
    puts "finish: #{@capability}"
  end

  def test_run
    setup

    # tap alert
    @appium.find_element(:name, 'Alerts').click
    @appium.wait_true do
      @appium.find_element(:name, 'Show OK-Cancel').click
      @appium.find_element(:name, 'UIActionSheet <title>').displayed?
    end
    @appium.alert action: 'accept'
    @appium.back

    sleep 5

    # TODO: fixme
    text_elem = @appium.text(@appium.app_strings['ButtonsExplain'])
    @appium.driver.action.click(text_elem).perform
    @appium.back

    teardown
  end
end

class TestParallelRunProcess
  def initialize(capability)
    @capability = capability
  end

  def setup
    @appium = Appium::Driver.new({ caps: @capability, appium_lib: des_server_caps }, false)
    Appium.promote_appium_methods TestParallelRunProcess, @appium
    start_driver
  end

  def teardown
    quit_driver
    puts "finish: #{@capability}"
  end

  def test_run
    setup

    # tap alert
    find_element(:name, 'Alerts').click
    wait_true do
      find_element(:name, 'Show OK-Cancel').click
      find_element(:name, 'UIActionSheet <title>').displayed?
    end
    alert action: 'accept'
    back

    sleep 5

    # TODO: fixme
    # TouchAction
    text_elem = text(app_strings['ButtonsExplain'])
    driver.action.click(text_elem).perform
    back

    teardown
  end
end
