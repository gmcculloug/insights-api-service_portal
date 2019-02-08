describe "PortfolioItemRequests", :type => :request do
  around do |example|
    bypass_tenancy do
      example.call
    end
  end

  let(:service_offering_ref) { "998" }
  let(:service_offering_source_ref) { "568" }
  let(:order) { create(:order) }
  let(:icon_id) { 1 }
  let(:portfolio_item) do
    create(:portfolio_item, :service_offering_ref        => service_offering_ref,
                            :service_offering_source_ref => service_offering_source_ref,
                            :service_offering_icon_ref   => icon_id)
  end
  let(:portfolio_item_id)    { portfolio_item.id }
  let(:topo_ex)              { Catalog::TopologyError.new("kaboom") }

  %w(admin user).each do |tag|
    describe "GET #{tag} /portfolio_items/:portfolio_item_id" do
      before do
        get "#{api}/portfolio_items/#{portfolio_item_id}", :headers => admin_headers
      end

      context 'the portfolio_item exists' do
        it 'returns status code 200' do
          expect(response).to have_http_status(200)
        end

        it 'returns the portfolio_item we asked for' do
          expect(json["id"]).to eq portfolio_item.id.to_s
        end
      end
    end
  end

  %w(admin user).each do |tag|
    describe "GET v1.0 #{tag} /portfolio_items/:portfolio_item_id" do
      before do
        get "#{api}/portfolio_items/#{portfolio_item_id}", :headers => admin_headers
      end

      context 'the portfolio_item exists' do
        it 'returns status code 200' do
          expect(response).to have_http_status(200)
        end

        it 'returns the portfolio_item we asked for' do
          expect(json["id"]).to eq portfolio_item.id.to_s
        end
      end
    end
  end

  describe 'DELETE admin tagged /portfolio_items/:portfolio_item_id' do
    # TODO: https://github.com/ManageIQ/catalog-api/issues/85
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'description for patched portfolio' } }

    context 'when v1.0 :portfolio_item_id is valid' do
      before do
        delete "#{api}/portfolio_items/#{portfolio_item_id}", :headers => admin_headers, :params => valid_attributes
      end

      it 'discards the record' do
        expect(response).to have_http_status(204)
      end

      it 'is still present in the db, just with deleted_at set' do
        expect(PortfolioItem.with_discarded.find_by(:id => portfolio_item_id).discarded_at).to_not be_nil
      end

      it "can't be requested" do
        expect { get("/#{api}/portfolio_items/#{portfolio_item_id}", :headers => admin_headers) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET portfolio items' do
    context "v1.0" do
      it "success" do
        portfolio_item
        get "/#{api}/portfolio_items"
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)['data'].count).to eq(1)
      end
    end
  end

  context "when adding portfolio items" do
    let(:add_to_portfolio_svc) { double(ServiceOffering::AddToPortfolioItem) }
    let(:params) { { :service_offering_ref => service_offering_ref } }

    before do
      allow(ServiceOffering::AddToPortfolioItem).to receive(:new).and_return(add_to_portfolio_svc)
    end

    it "returns not found when topology doesn't have the service_offering_ref" do
      allow(add_to_portfolio_svc).to receive(:process).and_raise(topo_ex)

      post "#{api}/portfolio_items", :params => params
      expect(response).to have_http_status(:not_found)
    end

    it "returns the new portfolio item when topology has the service_offering_ref" do
      allow(add_to_portfolio_svc).to receive(:process).and_return(add_to_portfolio_svc)
      allow(add_to_portfolio_svc).to receive(:item).and_return(portfolio_item)

      post "#{api}/portfolio_items", :params => params
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq portfolio_item.id.to_s
      expect(json["service_offering_ref"]).to eq service_offering_ref
    end
  end

  context "service plans" do
    let(:svc_object)           { instance_double("Catalog::ServicePlans") }
    let(:plans)                { [{}, {}] }

    before do
      allow(Catalog::ServicePlans).to receive(:new).with(portfolio_item.id.to_s).and_return(svc_object)
    end

    it "fetches plans" do
      allow(svc_object).to receive(:process).and_return(svc_object)
      allow(svc_object).to receive(:items).and_return(plans)

      get "/#{api}/portfolio_items/#{portfolio_item.id}/service_plans"

      expect(JSON.parse(response.body).count).to eq(2)
      expect(response.content_type).to eq("application/json")
      expect(response).to have_http_status(:ok)
    end

    it "raises error" do
      allow(svc_object).to receive(:process).and_raise(topo_ex)

      get "/#{api}/portfolio_items/#{portfolio_item.id}/service_plans"
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  context "v1.0 provider control parameters" do
    let(:svc_object)  { instance_double("Catalog::ProviderControlParameters") }
    let(:url)         { "#{api}/portfolio_items/#{portfolio_item.id}/provider_control_parameters" }

    before do
      allow(Catalog::ProviderControlParameters).to receive(:new).with(portfolio_item.id.to_s).and_return(svc_object)
    end

    it "fetches plans" do
      allow(svc_object).to receive(:process).and_return(svc_object)
      allow(svc_object).to receive(:data).and_return(:fred => 'bedrock')

      get url

      expect(response.content_type).to eq("application/json")
      expect(response).to have_http_status(:ok)
    end

    it "raises error" do
      allow(svc_object).to receive(:process).and_raise(topo_ex)

      get url

      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "patching portfolio items" do
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'PatchDescription', :workflow_ref => 'PatchWorkflowRef'} }
    let(:invalid_attributes) { { :name => 'PatchPortfolio', :service_offering_ref => "27" } }

    context "when passing in valid attributes" do
      before do
        patch "#{api}/portfolio_items/#{portfolio_item.id}", :params => valid_attributes, :headers => admin_headers
      end

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'patches the record' do
        expect(json).to include(valid_attributes.stringify_keys)
      end
    end

    context "when passing in read-only attributes" do
      before do
        patch "#{api}/portfolio_items/#{portfolio_item.id}", :params => invalid_attributes, :headers => admin_headers
      end

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'updates the field that is allowed' do
        expect(json["name"]).to eq invalid_attributes[:name]
      end

      it "does not update the read-only field" do
        expect(json["service_offering_ref"]).to_not eq invalid_attributes[:service_offering_ref]
      end
    end
  end

  context "icons" do
    let(:api_instance) { double }
    let(:topological_inventory) do
      class_double("TopologicalInventory")
        .as_stubbed_const(:transfer_nested_constants => true)
    end

    let(:topology_service_offering_icon) do
      TopologicalInventoryApiClient::ServiceOfferingIcon.new(
        :id         => icon_id,
        :source_ref => "src",
        :data       => "img"
      )
    end
    let(:portfolio_item_without_overriden_icon) do
      create(:portfolio_item,
             :service_offering_icon_ref => topology_service_offering_icon.id)
    end

    before do
      allow(topological_inventory).to receive(:call).and_yield(api_instance)
    end
    context "when we have to hit topology for the icon data" do
      it "reaches out to topology to get the icon" do
        expect(api_instance).to receive(:show_service_offering_icon).with(topology_service_offering_icon.id.to_s).and_return(topology_service_offering_icon)

        get "#{api('0.1')}/portfolio_items/#{portfolio_item_without_overriden_icon.id}/icon", :headers => admin_headers

        expect(response).to have_http_status(200)
        expect(json["id"]).to eq topology_service_offering_icon.id
      end
    end
  end
end
