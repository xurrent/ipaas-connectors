require 'spec_helper'

describe Boolean do
  it 'should resolve true to Boolean' do
    expect(true.is_a?(Boolean)).to be_truthy
  end

  it 'should resolve false to Boolean' do
    expect(false.is_a?(Boolean)).to be_truthy
  end

  it 'should not resolve nil to Boolean' do
    expect(nil.is_a?(Boolean)).to be_falsey
  end

  it 'should not resolve 1 to Boolean' do
    expect(1.is_a?(Boolean)).to be_falsey
  end
end
