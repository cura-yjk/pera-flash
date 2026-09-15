require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Was generated as `users_dashboard_url`, which has never been a route here
  # (it is `dashboard_path`), and it never signed in -- so the app's only
  # non-commented test had been failing since it was written.
  test "dashboard requires authentication" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "shows the dashboard to a signed-in user" do
    sign_in users(:learner)

    get dashboard_path

    assert_response :success
  end

  # The navbar renders on every signed-in page, so these guard the review queue
  # being reachable from anywhere -- not just the dashboard that used to own it.
  test "navbar links to the review queue when cards are due" do
    sign_in users(:learner)
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.day.ago)

    get dashboard_path

    assert_select "a[href=?]", review_path
  end

  test "navbar hides the review queue when nothing is due" do
    sign_in users(:learner)
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.week.from_now)

    get dashboard_path

    assert_select "a[href=?]", review_path, count: 0
  end

  test "navbar search goes to the flashcard index" do
    sign_in users(:learner)

    get dashboard_path

    assert_select "form[action=?][method=?]", flashcards_path, "get"
  end
end
