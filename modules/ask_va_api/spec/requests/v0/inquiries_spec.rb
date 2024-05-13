# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::V0::InquiriesController, type: :request do
  let(:inquiry_path) { '/ask_va_api/v0/inquiries' }
  let(:logger) { instance_double(LogService) }
  let(:span) { instance_double(Datadog::Tracing::Span) }
  let(:icn) { I18n.t('ask_va_api')[:test_users][:test_user_228_icn] }
  let(:authorized_user) { build(:user, :accountable_with_sec_id, icn:) }
  let(:mock_inquiries) do
    JSON.parse(File.read('modules/ask_va_api/config/locales/get_inquiries_mock_data.json'))['Data']
  end
  let(:valid_id) { mock_inquiries.first['InquiryNumber'] }
  let(:invalid_id) { 'A-20240423-30709' }

  before do
    allow(LogService).to receive(:new).and_return(logger)
    allow(logger).to receive(:call).and_yield(span)
    allow(span).to receive(:set_tag)
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('token')
  end

  shared_examples_for 'common error handling' do |status, action, error_message|
    it 'logs and renders error and sets datadog tags' do
      expect(response).to have_http_status(status)
      expect(JSON.parse(response.body)['error']).to eq(error_message)
      expect(logger).to have_received(:call).with(action)
      expect(span).to have_received(:set_tag).with('error', true)
      expect(span).to have_received(:set_tag).with('error.msg', error_message)
      expect(Rails.logger).to have_received(:error).with("Error during #{action}: #{error_message}")
    end
  end

  describe 'GET #index' do
    context 'when user is signed in' do
      before { sign_in(authorized_user) }

      context 'when everything is okay' do
        let(:json_response) do
          { 'id' => '1',
            'type' => 'inquiry',
            'attributes' =>
               { 'inquiry_number' => 'A-1',
                 'attachments' => [{ 'Id' => '1', 'Name' => 'testfile.txt' }],
                 'correspondences' => nil,
                 'has_attachments' => true,
                 'has_been_split' => true,
                 'level_of_authentication' => 'Personal',
                 'last_update' => '12/20/23',
                 'status' => 'In Progress',
                 'submitter_question' => 'What is my status?',
                 'school_facility_code' => '0123',
                 'topic' => 'Status of a pending claim',
                 'veteran_relationship' => 'self' } }
        end

        before { get inquiry_path, params: { mock: true } }

        it { expect(response).to have_http_status(:ok) }
        it { expect(JSON.parse(response.body)['data']).to include(json_response) }
      end

      context 'when an error occurs' do
        context 'when a service error' do
          let(:error_message) { 'service error' }

          before do
            allow_any_instance_of(Crm::Service)
              .to receive(:call)
              .and_raise(Crm::ErrorHandler::ServiceError.new(error_message))
            get inquiry_path
          end

          it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                          'Crm::ErrorHandler::ServiceError: service error'
        end

        context 'when a standard error' do
          let(:error_message) { 'standard error' }

          before do
            allow_any_instance_of(Crm::Service)
              .to receive(:call)
              .and_raise(StandardError.new(error_message))
            get inquiry_path
          end

          it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                          'StandardError: standard error'
        end
      end
    end

    context 'when user is not signed in' do
      before { get inquiry_path }

      it { expect(response).to have_http_status(:unauthorized) }
    end
  end

  describe 'GET #show' do
    let(:expected_response) do
      { 'data' =>
        { 'id' => '1',
          'type' => 'inquiry',
          'attributes' =>
          { 'inquiry_number' => 'A-1',
            'attachments' => [{ 'Id' => '1', 'Name' => 'testfile.txt' }],
            'correspondences' => { 'data' => [{
              'id' => '1',
              'type' => 'correspondence',
              'attributes' => {
                'message_type' => '722310001: Response from VA',
                'modified_on' => '1/2/23',
                'status_reason' => 'Completed/Sent',
                'description' => 'Your claim is still In Progress',
                'enable_reply' => true,
                'attachments' => [
                  {
                    'Id' => '12',
                    'Name' => 'correspondence_1_attachment.pdf'
                  }
                ]
              }
            }] },
            'has_attachments' => true,
            'has_been_split' => true,
            'level_of_authentication' => 'Personal',
            'last_update' => '12/20/23',
            'status' => 'In Progress',
            'submitter_question' => 'What is my status?',
            'school_facility_code' => '0123',
            'topic' => 'Status of a pending claim',
            'veteran_relationship' => 'self' } } }
    end

    context 'when user is signed in' do
      context 'when mock is given' do
        before do
          sign_in(authorized_user)
          get "#{inquiry_path}/#{valid_id}", params: { mock: true }
        end

        it { expect(response).to have_http_status(:ok) }
        it { expect(JSON.parse(response.body)).to eq(expected_response) }
      end

      context 'when mock is not given' do
        let(:crm_response) do
          { Data: [{ Id: '154163f2-8fbb-ed11-9ac4-00155da17a6f',
                     InquiryNumber: 'A-20230305-306178',
                     InquiryStatus: 'Reopened',
                     SubmitterQuestion: 'test',
                     LastUpdate: '4/1/2024 12:00:00 AM',
                     InquiryHasAttachments: true,
                     InquiryHasBeenSplit: true,
                     VeteranRelationship: 'GIBillBeneficiary',
                     SchoolFacilityCode: '77a51029-6816-e611-9436-0050568d743d',
                     InquiryTopic: 'Medical Care Concerns at a VA Medical Facility',
                     InquiryLevelOfAuthentication: 'Unauthenticated',
                     AttachmentNames: [{ Id: '367e8d31-6c82-1d3c-81b8-dd2cabed7555',
                                         Name: 'Test.txt' }] }] }
        end
        let(:expected_response) do
          { 'data' =>
            { 'id' => '154163f2-8fbb-ed11-9ac4-00155da17a6f',
              'type' => 'inquiry',
              'attributes' =>
              { 'inquiry_number' => 'A-20230305-306178',
                'attachments' => [{ 'Id' => '367e8d31-6c82-1d3c-81b8-dd2cabed7555', 'Name' => 'Test.txt' }],
                'correspondences' =>
                { 'data' =>
                  [{ 'id' => '154163f2-8fbb-ed11-9ac4-00155da17a6f',
                     'type' => 'correspondence',
                     'attributes' =>
                     { 'message_type' => nil,
                       'modified_on' => nil,
                       'status_reason' => nil,
                       'description' => nil,
                       'enable_reply' => nil,
                       'attachments' => [{ 'Id' => '367e8d31-6c82-1d3c-81b8-dd2cabed7555',
                                           'Name' => 'Test.txt' }] } }] },
                'has_attachments' => true,
                'has_been_split' => true,
                'level_of_authentication' => 'Unauthenticated',
                'last_update' => '4/1/2024 12:00:00 AM',
                'status' => 'Reopened',
                'submitter_question' => 'test',
                'school_facility_code' => '77a51029-6816-e611-9436-0050568d743d',
                'topic' => 'Medical Care Concerns at a VA Medical Facility',
                'veteran_relationship' => 'GIBillBeneficiary' } } }
        end
        let(:service) { instance_double(Crm::Service) }

        before do
          allow(Crm::Service).to receive(:new).and_return(service)
          allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('Token')
          allow(service).to receive(:call).and_return(crm_response)
          sign_in(authorized_user)
          get "#{inquiry_path}/#{valid_id}"
        end

        it { expect(response).to have_http_status(:ok) }
        it { expect(JSON.parse(response.body)).to eq(expected_response) }
      end

      context 'when the id is invalid' do
        let(:body) do
          '{"Data":null,"Message":"Data Validation: No Inquiries found by ID A-20240423-30709"' \
            ',"ExceptionOccurred":true,"ExceptionMessage":"Data Validation: No Inquiries found by ' \
            'ID A-20240423-30709","MessageId":"ca5b990a-63fe-407d-a364-46caffce12c1"}'
        end
        let(:failure) { Faraday::Response.new(response_body: body, status: 400) }
        let(:service) { instance_double(Crm::Service) }

        before do
          allow(Crm::Service).to receive(:new).and_return(service)
          allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('Token')
          allow(service).to receive(:call).and_return(failure)
          sign_in(authorized_user)
          get "#{inquiry_path}/#{invalid_id}"
        end

        it { expect(response).to have_http_status(:unprocessable_entity) }

        it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                        'AskVAApi::Inquiries::InquiriesRetrieverError: ' \
                        'Data Validation: No Inquiries found by ID A-20240423-30709'
      end
    end
  end

  describe 'GET #download_attachment' do
    let(:id) { '1' }

    before do
      sign_in(authorized_user)
    end

    context 'when successful' do
      before do
        get '/ask_va_api/v0/download_attachment', params: { id:, mock: true }
      end

      it 'response with 200' do
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when Crm raise an error' do
      let(:body) do
        '{"Data":null,"Message":"Data Validation: Invalid GUID, Parsing Failed",' \
          '"ExceptionOccurred":true,"ExceptionMessage":"Data Validation: Invalid GUID,' \
          ' Parsing Failed","MessageId":"c14c61c4-a3a8-4200-8c86-bdc09c261308"}'
      end
      let(:failure) { Faraday::Response.new(response_body: body, status: 400) }

      before do
        allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('token')
        allow_any_instance_of(Crm::Service).to receive(:call)
          .with(endpoint: 'attachment', payload: { id: '1' }).and_return(failure)
        get '/ask_va_api/v0/download_attachment', params: { id:, mock: nil }
      end

      it 'raise the error' do
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET #profile' do
    context 'when a user is signed in' do
      before do
        sign_in(authorized_user)
        get '/ask_va_api/v0/profile', params: { user_mock_data: true }
      end

      it 'response with 200' do
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occur' do
      before do
        allow_any_instance_of(Crm::Service).to receive(:call).and_raise(ErrorHandler::ServiceError)
        sign_in(authorized_user)
        get '/ask_va_api/v0/profile'
      end

      it {
        expect(JSON.parse(response.body)).to eq('error' => 'ErrorHandler::ServiceError: ErrorHandler::ServiceError')
      }
    end

    context 'when user is not signed in' do
      before do
        get '/ask_va_api/v0/profile'
      end

      it { expect(response).to have_http_status(:unauthorized) }
    end

    context 'when a user does not have a profile' do
      let(:icn) { '1013694290V263188' }
      let(:profile_user) { build(:user, :accountable_with_sec_id, icn:) }

      before do
        sign_in(profile_user)
        get '/ask_va_api/v0/profile', params: { user_mock_data: true }
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'AskVAApi::Profile::InvalidInquiryError: No Contact found'
    end
  end

  describe 'GET #status' do
    before do
      allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('Token')
      allow_any_instance_of(Crm::Service)
        .to receive(:call).and_return({
                                        Status: 'Reopened',
                                        Message: nil,
                                        ExceptionOccurred: false,
                                        ExceptionMessage: nil,
                                        MessageId: 'c6252e77-cf7f-48b6-96be-1b43d8e9905c'
                                      })
      sign_in(authorized_user)
      get "/ask_va_api/v0/inquiries/#{valid_id}/status"
    end

    it 'returns the status for the given inquiry id' do
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['data']).to eq({ 'id' => nil,
                                                        'type' => 'inquiry_status',
                                                        'attributes' => { 'status' => 'Reopened' } })
    end
  end

  describe 'POST #create' do
    let(:payload) { { FirstName: 'Fake', YourLastName: 'Smith' } }
    let(:endpoint) { AskVAApi::Inquiries::Creator::ENDPOINT }

    context 'when successful' do
      before do
        allow_any_instance_of(Crm::Service).to receive(:call)
          .with(endpoint:, method: :put,
                payload:).and_return({
                                       Data: {
                                         Id: '530d56a8-affd-ee11-a1fe-001dd8094ff1'
                                       },
                                       Message: '',
                                       ExceptionOccurred: false,
                                       ExceptionMessage: '',
                                       MessageId: 'b8ebd8e7-3bbf-49c5-aff0-99503e50ee27'
                                     })
        sign_in(authorized_user)
        post '/ask_va_api/v0/inquiries/auth', params: payload
      end

      it { expect(response).to have_http_status(:created) }
    end

    context 'when crm api fail' do
      context 'when the API call fails' do
        let(:body) do
          '{"Data":null,"Message":"Data Validation: missing InquiryCategory"' \
            ',"ExceptionOccurred":true,"ExceptionMessage":"Data Validation: missing' \
            'InquiryCategory","MessageId":"cb0dd954-ef25-4e56-b0d9-41925e5a190c"}'
        end
        let(:failure) { Faraday::Response.new(response_body: body, status: 400) }

        before do
          allow_any_instance_of(Crm::Service).to receive(:call)
            .with(endpoint:, method: :put,
                  payload:).and_return(failure)
          sign_in(authorized_user)
          post '/ask_va_api/v0/inquiries/auth', params: payload
        end

        it 'raise InquiriesCreatorError' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                        'AskVAApi::Inquiries::InquiriesCreatorError: Data Validation: missing InquiryCategory'
      end
    end
  end

  describe 'POST #unauth_create' do
    let(:payload) { { FirstName: 'Fake', YourLastName: 'Smith' } }
    let(:endpoint) { AskVAApi::Inquiries::Creator::ENDPOINT }

    context 'when successful' do
      before do
        allow_any_instance_of(Crm::Service).to receive(:call)
          .with(endpoint:, method: :put,
                payload:).and_return({
                                       Data: {
                                         Id: '530d56a8-affd-ee11-a1fe-001dd8094ff1'
                                       },
                                       Message: '',
                                       ExceptionOccurred: false,
                                       ExceptionMessage: '',
                                       MessageId: 'b8ebd8e7-3bbf-49c5-aff0-99503e50ee27'
                                     })
        post inquiry_path, params: payload
      end

      it { expect(response).to have_http_status(:created) }
    end

    context 'when crm api fail' do
      context 'when the API call fails' do
        let(:body) do
          '{"Data":null,"Message":"Data Validation: missing InquiryCategory"' \
            ',"ExceptionOccurred":true,"ExceptionMessage":"Data Validation: missing' \
            'InquiryCategory","MessageId":"cb0dd954-ef25-4e56-b0d9-41925e5a190c"}'
        end
        let(:failure) { Faraday::Response.new(response_body: body, status: 400) }

        before do
          allow_any_instance_of(Crm::Service).to receive(:call)
            .with(endpoint:, method: :put,
                  payload:).and_return(failure)
          post '/ask_va_api/v0/inquiries', params: payload
        end

        it 'raise InquiriesCreatorError' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                        'AskVAApi::Inquiries::InquiriesCreatorError: Data Validation: missing InquiryCategory'
      end
    end
  end

  describe 'POST #upload_attachment' do
    let(:file_path) { 'modules/ask_va_api/config/locales/get_inquiries_mock_data.json' }
    let(:base64_encoded_file) { Base64.strict_encode64(File.read(file_path)) }
    let(:file) { "data:image/png;base64,#{base64_encoded_file}" }
    let(:inquiry_id) { '1c1f5631-9edf-ee11-904d-001dd8306b36' }
    let(:correspondence_id) { nil }
    let(:params) do
      {
        file_name: 'testfile',
        file_content: file,
        inquiry_id:,
        correspondence_id:
      }
    end

    context 'when successful' do
      let(:crm_response) do
        { Data: {
          Id: '1c1f5631-9edf-ee11-904d-001dd8306b36'
        } }
      end

      before do
        allow_any_instance_of(Crm::Service).to receive(:call)
          .with(endpoint: 'attachment/new', payload: {
                  inquiryId: params[:inquiry_id],
                  fileName: params[:file_name],
                  fileContent: file,
                  correspondenceId: params[:correspondence_id]
                }).and_return(crm_response)

        post '/ask_va_api/v0/upload_attachment', params:
      end

      it 'returns http status :ok' do
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST #create_reply' do
    let(:payload) { { 'reply' => 'this is my reply' } }

    context 'when successful' do
      before do
        allow_any_instance_of(Crm::Service).to receive(:call).and_return({ Data: { Id: '123' } })
        sign_in(authorized_user)
        post '/ask_va_api/v0/inquiries/123/reply/new', params: payload
      end

      it 'returns status 200' do
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when crm api fail' do
      context 'when the API call fails' do
        let(:endpoint) { 'inquiries/123/reply/new' }
        let(:body) do
          '{"Data":null,"Message":"Data Validation: Missing Reply"' \
            ',"ExceptionOccurred":true,"ExceptionMessage":"Data Validation: ' \
            'Missing Reply","MessageId":"e2cbe041-df91-41f4-8bd2-8b6d9dbb2e38"}'
        end
        let(:failure) { Faraday::Response.new(response_body: body, status: 400) }

        before do
          sign_in(authorized_user)
          allow_any_instance_of(Crm::Service).to receive(:call)
            .with(endpoint:, method: :put,
                  payload: { Reply: 'this is my reply' }).and_return(failure)
          post '/ask_va_api/v0/inquiries/123/reply/new', params: payload
        end

        it 'raise InquiriesCreatorError' do
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                        'AskVAApi::Correspondences::CorrespondencesCreatorError: Data Validation: Missing Reply'
      end
    end
  end
end
