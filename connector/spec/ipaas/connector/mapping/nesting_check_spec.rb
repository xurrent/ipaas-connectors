require 'spec_helper'

describe IPaaS::Connector::Mapping::NestingCheck do
  def problem(value, max_depth: described_class::MAX_DEPTH)
    described_class.problem(value, max_depth: max_depth)
  end

  def nest(levels, inner = [])
    (2..levels).reduce(inner) { |nested, _| [nested] }
  end

  context 'a value that contains itself' do
    it 'finds an array that includes itself' do
      list = ['a']
      list << list
      expect(problem(list)).to eq(:contains_itself)
    end

    it 'finds a hash that includes itself' do
      hash = { 'a' => 1 }
      hash['self'] = hash
      expect(problem(hash)).to eq(:contains_itself)
    end

    it 'finds a hash that includes itself as a key' do
      hash = {}
      hash[[hash]] = 1
      expect(problem(hash)).to eq(:contains_itself)
    end

    it 'finds a cycle that passes through a hash further down' do
      list = []
      list << [{ 'items' => [list] }]
      expect(problem(['root', list])).to eq(:contains_itself)
    end

    it 'does not take a value that appears twice for one that includes itself' do
      shared = { 'a' => [1] }
      expect(problem([shared, { 'again' => shared }, [shared]])).to be_nil
    end

    it 'does not take two equal but separate values for one that includes itself' do
      expect(problem([[1], [1]])).to be_nil
      expect(problem([{ 'a' => 1 }, { 'a' => 1 }])).to be_nil
    end

    it 'finishes on a value shared along 2**64 paths' do
      diamonds = (1..64).reduce(['leaf']) { |inner, _| [inner, inner] }
      expect(Timeout.timeout(5) { problem(diamonds, max_depth: Float::INFINITY) }).to be_nil
    end

    it 'still finds a cycle after skipping an already finished value' do
      shared = [1]
      list = []
      list.push([list], shared, shared)
      expect(problem(list)).to eq(:contains_itself)
    end

    it 'finds a hash with indifferent access that includes itself' do
      hash = { 'a' => 1 }.with_indifferent_access
      hash.store('self', hash)
      expect(problem(hash)).to eq(:contains_itself)
    end
  end

  context 'a value nested too deeply' do
    it 'accepts nesting up to the bound and rejects one level more' do
      expect(problem(nest(3), max_depth: 3)).to be_nil
      expect(problem(nest(4), max_depth: 3)).to eq(:too_deep)
    end

    it 'counts the levels inside a hash' do
      expect(problem({ 'a' => { 'b' => [1] } }, max_depth: 3)).to be_nil
      expect(problem({ 'a' => { 'b' => [[1]] } }, max_depth: 3)).to eq(:too_deep)
    end

    it 'counts the levels inside a hash key' do
      expect(problem({ [[1]] => 1 }, max_depth: 3)).to be_nil
      expect(problem({ [[[1]]] => 1 }, max_depth: 3)).to eq(:too_deep)
    end

    it 'rejects a shared value where it is reached too deeply after it was walked shallowly' do
      shared = nest(2)
      expect(problem([nest(2, shared), shared], max_depth: 3)).to eq(:too_deep)
      expect(problem([nest(1, shared), shared], max_depth: 3)).to be_nil
    end

    it 'counts the deepest member of a shared value inside another shared value' do
      shared = [[], nest(3)]
      wrapper = [shared]
      value = [[wrapper], wrapper, shared]
      expect(problem(value, max_depth: 6)).to eq(:too_deep)
      expect(problem(value, max_depth: 7)).to be_nil
    end

    it 'allows what JSON.generate serializes and rejects what it refuses' do
      at_bound = nest(described_class::MAX_DEPTH)
      past_bound = nest(described_class::MAX_DEPTH + 1)
      expect { JSON.generate(at_bound) }.not_to raise_error
      expect(problem(at_bound)).to be_nil
      expect { JSON.generate(past_bound) }.to raise_error(JSON::NestingError)
      expect(problem(past_bound)).to eq(:too_deep)
    end
  end

  it 'walks nesting deeper than a recursive walk survives' do
    deep = nest(100_000)
    recursive_walk = Thread.new do
      Thread.current.report_on_exception = false
      deep.deep_dup
    end
    expect { recursive_walk.join }.to raise_error(SystemStackError)
    expect(Thread.new { problem(deep, max_depth: Float::INFINITY) }.value).to be_nil
  end

  it 'finds nothing in empty collections or values other than arrays and hashes' do
    expect([[], {}, nil, 'text', 1, :sym].map { |value| problem(value) }).to all(be_nil)
  end
end
