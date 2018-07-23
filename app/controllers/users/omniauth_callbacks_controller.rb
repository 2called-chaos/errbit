class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    github_user = lookup_github_user

    if github_user.blank? && github_org_id.present?
      if member_of_supported_github_organization?
      # If they are, automatically create an account
        github_user = User.create(
          name: omniauth_github_raw_info.name,
          email: omniauth_github_raw_info.email
        )
      end
    end

    # If user is already signed in, link github details to their account
    if current_user
      # ... unless a user is already registered with same github login
      if github_user && github_user != current_user
        flash[:error] = "User already registered with #{github_site_title} login '#{github_login}'!"
      else
        # Add github details to current user
        update_user_with_github_attributes(current_user, github_login, github_token)
        flash[:success] = "Successfully linked #{github_site_title} account!"
      end
      # User must have clicked 'link account' from their user page, so redirect there.
      redirect_to user_path(current_user)
    elsif github_user
      # Store OAuth token
      update_user_with_github_attributes(github_user, github_login, github_token)
      flash[:success] = I18n.t "devise.omniauth_callbacks.success", kind: github_site_title
      sign_in_and_redirect github_user, event: :authentication
    else
      flash[:error] = "There are no authorized users with #{github_site_title} login '#{github_login}'. Please ask an administrator to register your user account."
      redirect_to new_user_session_path
    end
  end

  def google_oauth2
    google_uid = env['omniauth.auth'].uid
    google_email = env['omniauth.auth'].info.email
    google_user = User.where(google_uid: google_uid).first
    google_site_title = Errbit::Config.google_site_title
    # If user is already signed in, link google details to their account
    if current_user
      # ... unless a user is already registered with same google login
      if google_user && google_user != current_user
        flash[:error] = "User already registered with #{google_site_title} login '#{google_email}'!"
      else
        # Add google details to current user
        current_user.update(google_uid: google_uid)
        flash[:success] = "Successfully linked #{google_email} account!"
      end
      # User must have clicked 'link account' from their user page, so redirect there.
      redirect_to user_path(current_user)
    elsif google_user
      flash[:success] = I18n.t 'devise.omniauth_callbacks.success', kind: google_site_title
      sign_in_and_redirect google_user, event: :authentication
    elsif Errbit::Config.google_auto_provision
      if User.valid_google_domain?(google_email)
        user = User.create_from_google_oauth2(request.env['omniauth.auth'])
        if user.persisted?
          flash[:notice] = I18n.t "devise.omniauth_callbacks.success", kind: google_site_title
          sign_in_and_redirect user, event: :authentication
        else
          session['devise.google_data'] = request.env['omniauth.auth'].except(:extra)
          redirect_to new_user_session_path, alert: user.errors.full_messages.join("\n")
        end
      else
        flash[:error] = I18n.t "devise.google_login.domain_unauthorized"
        redirect_to new_user_session_path
      end
    else
      flash[:error] = "There are no authorized users with #{google_site_title} login '#{google_email}'. Please ask an administrator to register your user account."
      redirect_to new_user_session_path
    end
  end

private

  def omniauth_github_raw_info
    env["omniauth.auth"].extra.raw_info
  end

  def member_of_supported_github_organization?
    client = Octokit::Client.new(access_token: github_token)
    client.api_endpoint = Errbit::Config.github_api_url
    client.organizations.map(&:id).include?(github_org_id)
  end

  def lookup_github_user
    User.where(github_login: github_login).first
  end

  def github_org_id
    Errbit::Config.github_org_id
  end

  def github_site_title
    Errbit::Config.github_site_title
  end

  def github_login
    omniauth_github_raw_info.login
  end

  def github_token
    env["omniauth.auth"].credentials.token
  end

  def update_user_with_github_attributes(user, login, token)
    user.update_attributes(
      github_login:       login,
      github_oauth_token: token
    )
  end
end
