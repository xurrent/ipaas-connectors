require 'spec_helper'

describe IPaaS::Job::Helpers do
  let(:context) { Class.new { include IPaaS::Job::Helpers }.new }

  describe 'camel_to_snake' do
    it 'converts camelCase hash keys to snake_case symbols' do
      input = { 'firstName' => 'John', 'lastName' => 'Doe' }
      expected = { first_name: 'John', last_name: 'Doe' }

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    it 'converts PascalCase hash keys to snake_case symbols' do
      input = { 'FirstName' => 'John', 'LastName' => 'Doe' }
      expected = { first_name: 'John', last_name: 'Doe' }

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    it 'recursively converts nested hashes' do
      input = {
        'userInfo' => {
          'firstName' => 'John',
          'contactDetails' => {
            'emailAddress' => 'john@example.com',
          },
        },
      }
      expected = {
        user_info: {
          first_name: 'John',
          contact_details: {
            email_address: 'john@example.com',
          },
        },
      }

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    it 'converts arrays of hashes' do
      input = [
        { 'firstName' => 'John' },
        { 'firstName' => 'Jane' },
      ]
      expected = [
        { first_name: 'John' },
        { first_name: 'Jane' },
      ]

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    it 'handles nested arrays within hashes' do
      input = {
        'userList' => [
          { 'userName' => 'john' },
          { 'userName' => 'jane' },
        ],
      }
      expected = {
        user_list: [
          { user_name: 'john' },
          { user_name: 'jane' },
        ],
      }

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    context 'with non-hash non-array values' do
      it { expect(context.camel_to_snake('string')).to eq('string') }
      it { expect(context.camel_to_snake(123)).to eq(123) }
      it { expect(context.camel_to_snake(nil)).to be_nil }
      it { expect(context.camel_to_snake(true)).to eq(true) }
    end

    it 'handles empty hash' do
      expect(context.camel_to_snake({})).to eq({})
    end

    it 'handles empty array' do
      expect(context.camel_to_snake([])).to eq([])
    end

    it 'converts symbol keys to snake_case symbols' do
      input = { firstName: 'John', lastName: 'Doe' }
      expected = { first_name: 'John', last_name: 'Doe' }

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    it 'handles mixed arrays with primitives and hashes' do
      input = [
        { 'itemName' => 'first' },
        'plain string',
        42,
        { 'anotherItem' => 'second' },
      ]
      expected = [
        { item_name: 'first' },
        'plain string',
        42,
        { another_item: 'second' },
      ]

      expect(context.camel_to_snake(input)).to eq(expected)
    end

    context 'when skip_keys are provided' do
      it 'preserves original keys and nested content' do
        input = {
          'hostName' => 'host-1',
          'cpuCores' => {
            'stillCamel' => 12,
          },
          'socket-hostname' => {
            'still-kebab' => 'host-1.example.com',
          },
          'tags_by_source' => {
            'AWS' => [{ 'tagName' => 'Name' }],
          },
        }
        expected = {
          host_name: 'host-1',
          'cpuCores' => {
            'stillCamel' => 12,
          },
          'socket-hostname' => {
            'still-kebab' => 'host-1.example.com',
          },
          'tags_by_source' => {
            'AWS' => [{ 'tagName' => 'Name' }],
          },
        }

        expect(context.camel_to_snake(input, [:cpu_cores, :socket_hostname, :tags_by_source])).to eq(expected)
      end
    end

    it 'converts camelCase and kebab-case keys in one pass' do
      input = {
        'cpuCores' => 12,
        'socket-hostname' => 'host-1',
        'installMethod' => {
          'tool-version' => 'install_script',
        },
      }
      expected = {
        cpu_cores: 12,
        socket_hostname: 'host-1',
        install_method: {
          tool_version: 'install_script',
        },
      }

      expect(context.camel_to_snake(input)).to eq(expected)
    end
  end

  describe 'keys_to_field_id' do
    it 'preserves original case of hash keys' do
      input = { 'firstName' => 'John', 'lastName' => 'Doe' }
      expected = { firstName: 'John', lastName: 'Doe' }

      expect(context.keys_to_field_id(input)).to eq(expected)
    end

    it 'replaces non-alphanumeric characters with underscores' do
      input = { 'socket-hostname' => 'host-1', 'user.email' => 'a@b.com' }
      expected = { socket_hostname: 'host-1', user_email: 'a@b.com' }

      expect(context.keys_to_field_id(input)).to eq(expected)
    end

    it 'recursively converts nested hashes preserving case' do
      input = {
        'userInfo' => {
          'firstName' => 'John',
          'contactDetails' => {
            'emailAddress' => 'john@example.com',
          },
        },
      }
      expected = {
        userInfo: {
          firstName: 'John',
          contactDetails: {
            emailAddress: 'john@example.com',
          },
        },
      }

      expect(context.keys_to_field_id(input)).to eq(expected)
    end

    it 'converts nested hashes inside arrays preserving case' do
      input = {
        'itemList' => [
          { 'itemName' => 'first', 'itemType' => 'A' },
          { 'itemName' => 'second', 'itemType' => 'B' },
        ],
      }
      expected = {
        itemList: [
          { itemName: 'first', itemType: 'A' },
          { itemName: 'second', itemType: 'B' },
        ],
      }

      expect(context.keys_to_field_id(input)).to eq(expected)
    end

    it 'converts top-level arrays of hashes preserving case' do
      input = [{ 'firstName' => 'John' }, { 'firstName' => 'Jane' }]
      expected = [{ firstName: 'John' }, { firstName: 'Jane' }]

      expect(context.keys_to_field_id(input)).to eq(expected)
    end

    it 'truncates keys to 40 characters' do
      long_key = 'a_very_long_key_name_that_exceeds_forty_characters_total'
      result = context.keys_to_field_id({ long_key => 'val' })

      expect(result.keys.first.to_s.length).to be <= 40
    end

    it 'squeezes consecutive underscores' do
      input = { 'foo--bar' => 'val' }

      expect(context.keys_to_field_id(input)).to eq({ foo_bar: 'val' })
    end

    it 'strips leading and trailing underscores' do
      input = { '_leading' => 'a', 'trailing_' => 'b' }

      expect(context.keys_to_field_id(input)).to eq({ leading: 'a', trailing: 'b' })
    end

    context 'with non-hash non-array values' do
      it { expect(context.keys_to_field_id('string')).to eq('string') }
      it { expect(context.keys_to_field_id(123)).to eq(123) }
      it { expect(context.keys_to_field_id(nil)).to be_nil }
    end

    it 'handles empty hash and empty array' do
      expect(context.keys_to_field_id({})).to eq({})
      expect(context.keys_to_field_id([])).to eq([])
    end
  end
end
