class Kaui::AdminTenantsController < Kaui::EngineController

  skip_before_filter :check_for_redirect_to_tenant_screen

  def index
    # Display the configured tenants in KAUI (which could be different than the existing tenants known by Kill Bill)
    tenants_for_current_user = retrieve_tenants_for_current_user
    @tenants = Kaui::Tenant.all.select { |tenant| tenants_for_current_user.include?(tenant.kb_tenant_id) }
  end

  def new
    @tenant = Kaui::Tenant.new
  end

  def create
    param_tenant = params[:tenant]
    old_tenant = Kaui::Tenant.find_by_name(param_tenant[:name])
    if old_tenant
      flash.now[:error] = "Tenant with name #{param_tenant[:name]} already exists!"
      @tenant = Kaui::Tenant.new
      render :new and return
    end

    old_tenant = Kaui::Tenant.find_by_api_key(param_tenant[:api_key])
    if old_tenant
      flash.now[:error] = "Tenant with api key #{param_tenant[:api_key]} already exists!"
      @tenant = Kaui::Tenant.new
      render :new and return
    end

    begin
      options = tenant_options_for_client
      new_tenant = nil

      begin
        options[:api_key] = param_tenant[:api_key]
        options[:api_secret] = param_tenant[:api_secret]
        new_tenant = Kaui::AdminTenant.find_by_api_key(param_tenant[:api_key], options)
      rescue KillBillClient::API::Unauthorized, KillBillClient::API::NotFound
        # Create the tenant in Kill Bill
        new_tenant = Kaui::AdminTenant.new
        new_tenant.external_key = param_tenant[:name]
        new_tenant.api_key = param_tenant[:api_key]
        new_tenant.api_secret = param_tenant[:api_secret]
        new_tenant = new_tenant.create(options[:username], nil, comment, options)
      end

      # Transform object to Kaui model
      tenant_model = Kaui::Tenant.new
      tenant_model.name = new_tenant.external_key
      tenant_model.kb_tenant_id = new_tenant.tenant_id
      tenant_model.api_key = new_tenant.api_key
      tenant_model.api_secret = param_tenant[:api_secret]

      # Save in KAUI tables
      tenant_model.save!

      # Make sure at least the current user can access the tenant
      tenant_model.kaui_allowed_users << Kaui::AllowedUser.where(:kb_username => current_user.kb_username).first_or_create
    rescue => e
      flash[:error] = "Failed to create the tenant: #{as_string(e)}"
      redirect_to admin_tenants_path and return
    end

    # Select the tenant, see TenantsController
    session[:kb_tenant_id] = tenant_model.kb_tenant_id
    session[:kb_tenant_name] = tenant_model.name

    redirect_to admin_tenant_path(tenant_model[:id]), :notice => 'Tenant was successfully configured'
  end

  def show
    @tenant = safely_find_tenant_by_id(params[:id])
    @allowed_users = @tenant.kaui_allowed_users & retrieve_allowed_users_for_current_user
  end

  def upload_catalog
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    uploaded_catalog = params[:catalog]
    catalog_xml = uploaded_catalog.read

    Kaui::AdminTenant.upload_catalog(catalog_xml, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Catalog was successfully uploaded'
  end

  def upload_overdue_config
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    uploaded_overdue_config = params[:overdue]
    overdue_config_xml = uploaded_overdue_config.read

    Kaui::AdminTenant.upload_overdue_config(overdue_config_xml, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Overdue config was successfully uploaded'
  end


  def upload_invoice_template
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    is_manual_pay = params[:manual_pay]
    uploaded_invoice_template = params[:invoice_template]
    invoice_template = uploaded_invoice_template.read

    Kaui::AdminTenant.upload_invoice_template(invoice_template, is_manual_pay, true, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Invoice template was successfully uploaded'
  end

  def upload_invoice_translation
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    locale = params[:translation_locale]
    uploaded_invoice_translation = params[:invoice_translation]
    invoice_translation = uploaded_invoice_translation.read

    Kaui::AdminTenant.upload_invoice_translation(invoice_translation, locale, true, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Invoice translation was successfully uploaded'
  end

  def upload_catalog_translation
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    locale = params[:translation_locale]
    uploaded_catalog_translation = params[:catalog_translation]
    catalog_translation = uploaded_catalog_translation.read

    Kaui::AdminTenant.upload_catalog_translation(catalog_translation, locale, true, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Catalog translation was successfully uploaded'
  end

  def upload_plugin_config
    current_tenant = safely_find_tenant_by_id(params[:id])

    options = tenant_options_for_client
    options[:api_key] = current_tenant.api_key
    options[:api_secret] = current_tenant.api_secret

    plugin_name = params[:plugin_name]
    uploaded_plugin_config = params[:plugin_config]
    plugin_config = uploaded_plugin_config.read

    Kaui::AdminTenant.upload_tenant_plugin_config(plugin_name, plugin_config, options[:username], nil, comment, options)

    redirect_to admin_tenant_path(current_tenant.id), :notice => 'Config for plugin was successfully uploaded'
  end

  def remove_allowed_user
    current_tenant = safely_find_tenant_by_id(params[:id])
    au = Kaui::AllowedUser.find(params[:allowed_user][:id])
    # remove the association
    au.kaui_tenants.delete current_tenant
    render :json => '{}', :status => 200
  end

  private

  def safely_find_tenant_by_id(tenant_id)
    tenant = Kaui::Tenant.find_by_id(tenant_id)
    raise ActiveRecord::RecordNotFound.new('Could not find tenant ' + tenant_id) unless retrieve_tenants_for_current_user.include?(tenant.kb_tenant_id)
    tenant
  end

  def tenant_options_for_client
    user = current_user
    {
        :username => user.kb_username,
        :password => user.password,
        :session_id => user.kb_session_id
    }
  end

  def comment
    'Multi-tenant Administrative operation'
  end
end
