require 'spec_helper'

describe IPaaS::Connector::CoreExt::Drill do
  describe 'Hash#drill' do
    let(:hash) { { user: { name: 'Ann', address: { city: 'Ede' } } } }

    it 'returns the value for a single key' do
      expect(hash.drill(:user)).to eq(name: 'Ann', address: { city: 'Ede' })
    end

    it 'recurses through nested hashes' do
      expect(hash.drill(:user, :address, :city)).to eq('Ede')
    end

    it 'differs from dig when the path passes through an array' do
      data = { items: [{ name: 'Foo' }] }
      expect(data.drill(:items, :name)).to eq(['Foo'])
      expect { data.dig(:items, :name) }.to raise_error(TypeError)
    end

    it 'returns nil for a missing key' do
      expect(hash.drill(:user, :email)).to be_nil
    end

    it 'returns nil when the path hits nil mid-path' do
      expect({ user: nil }.drill(:user, :name)).to be_nil
    end

    it 'raises TypeError when the path hits a scalar mid-path' do
      expect { hash.drill(:user, :name, :first) }
        .to raise_error(TypeError, 'String does not have #drill method')
    end

    it 'resolves symbol and string keys on a HashWithIndifferentAccess but not on a string-keyed hash' do
      plain = { 'items' => [{ 'name' => 'Foo' }] }
      hwia = plain.with_indifferent_access
      expect(hwia.drill(:items, :name)).to eq(['Foo'])
      expect(hwia.drill('items', 'name')).to eq(['Foo'])
      expect(plain.drill(:items, :name)).to be_nil
    end
  end

  describe 'Array#drill' do
    let(:items) { [{ name: 'Foo', tags: ['a'] }, { name: 'Bar', tags: %w[b c] }] }

    context 'with an Integer key' do
      it 'selects the element at the index and recurses like dig' do
        expect(items.drill(0, :name)).to eq('Foo')
      end

      it 'returns nil for an out-of-range index' do
        expect(items.drill(5, :name)).to be_nil
      end
    end

    context 'with a non-Integer key' do
      it 'maps the key over each element' do
        expect(items.drill(:name)).to eq(%w[Foo Bar])
      end

      it 'applies the remaining path to each element' do
        data = [{ price: { amount: 5 } }, { price: { amount: 7 } }]
        expect(data.drill(:price, :amount)).to eq([5, 7])
      end

      it 'preserves nil entries for elements missing the key' do
        expect([{ name: 'Foo' }, {}].drill(:name)).to eq(['Foo', nil])
      end

      it 'preserves nil entries for nil elements' do
        expect([{ name: 'Foo' }, nil].drill(:name)).to eq(['Foo', nil])
      end

      it 'keeps nested arrays nested' do
        expect(items.drill(:tags)).to eq([['a'], %w[b c]])
      end

      it 'returns an empty array for an empty array' do
        expect([].drill(:name)).to eq([])
      end

      it 'raises TypeError when an element has a scalar where the path continues' do
        data = [{ price: { amount: 5 } }, { price: 'free' }]
        expect { data.drill(:price, :amount) }
          .to raise_error(TypeError, 'String does not have #drill method')
      end
    end
  end
end
