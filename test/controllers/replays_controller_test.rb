require "test_helper"

class ReplaysControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get replays_index_url
    assert_response :success
  end

  test "should get show" do
    get replays_show_url
    assert_response :success
  end

  test "should get new" do
    get replays_new_url
    assert_response :success
  end

  test "should get create" do
    get replays_create_url
    assert_response :success
  end
end
