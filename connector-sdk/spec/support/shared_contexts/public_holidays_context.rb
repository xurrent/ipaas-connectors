shared_context 'public holidays', :public_holidays do
  let(:connector_id) { '01a1d0f0-edb0-71a4-a345-f2b92534e646' }
  let(:base_url) { 'https://date.nager.at' }
  let(:outbound_connection_config) { { base_url: base_url } }

  def expect_reschedule_after(seconds, &step)
    Timecop.freeze do
      expect(&step).to raise_error(IPaaS::Job::RescheduleJob) do |error|
        expect(error.reschedule_after).to eq(seconds.seconds.from_now)
      end
    end
  end
end
