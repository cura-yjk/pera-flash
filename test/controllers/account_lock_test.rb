require "test_helper"

# Sign-up is open, so the sign-in form was a password-guessing endpoint with no
# ceiling on attempts. Driven through the real sign-in path, because the
# counting happens inside Devise's authentication, not in a model method.
class AccountLockTest < ActionDispatch::IntegrationTest
  setup { @user = users(:learner) }

  test "locks the account after too many wrong passwords" do
    Devise.maximum_attempts.times { attempt_sign_in("wrong-password") }

    assert_predicate @user.reload, :access_locked?
  end

  test "the right password no longer works while locked" do
    Devise.maximum_attempts.times { attempt_sign_in("wrong-password") }

    attempt_sign_in("password123")

    # Devise re-renders the form rather than redirecting, so the status is the
    # tell: the correct password did not get them in.
    assert_response :unprocessable_content
    assert_nil controller.current_user
  end

  test "a few mistakes do not lock anyone out" do
    3.times { attempt_sign_in("wrong-password") }

    attempt_sign_in("password123")

    assert_redirected_to dashboard_path
    assert_not @user.reload.access_locked?
  end

  # Unlocking is on a timer, not by email: this app has no SMTP configured, so
  # an unlock mail would never arrive and the lock would be permanent.
  test "unlocks itself once the wait has passed" do
    Devise.maximum_attempts.times { attempt_sign_in("wrong-password") }
    assert_predicate @user.reload, :access_locked?

    travel(Devise.unlock_in + 1.minute) do
      attempt_sign_in("password123")

      assert_redirected_to dashboard_path
    end
  end

  test "unlocking does not depend on email" do
    assert_equal :time, Devise.unlock_strategy
  end

  private

  def attempt_sign_in(password)
    post user_session_path, params: { user: { email: @user.email, password: password } }
  end
end
