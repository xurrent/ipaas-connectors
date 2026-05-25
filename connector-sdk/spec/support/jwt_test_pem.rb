module JwtTestPem
  ES256 = {
    private: <<~PEM.freeze,
      -----BEGIN EC PRIVATE KEY-----
      MHcCAQEEIC3e4UdeURm/xjcTTR0Y1poOYLHk286Vww/Mb76/rn2AoAoGCCqGSM49
      AwEHoUQDQgAEtG7reYmvMm5Wt5zcIuDNqZkZMnbvWO3OBRDR1w+psk4AAGAp3zYs
      p2ylkDqdLMcKXgMBSxAWCoX6LiC3dmHj4A==
      -----END EC PRIVATE KEY-----
    PEM
    public: <<~PEM.freeze,
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtG7reYmvMm5Wt5zcIuDNqZkZMnbv
      WO3OBRDR1w+psk4AAGAp3zYsp2ylkDqdLMcKXgMBSxAWCoX6LiC3dmHj4A==
      -----END PUBLIC KEY-----
    PEM
  }.freeze
end
