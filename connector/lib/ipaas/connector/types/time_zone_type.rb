module IPaaS
  def self.use_time_zone(time_zone, &block)
    Time.use_zone(IPaaS::Connector::Types::TimeZoneType.time_zone(time_zone), &block)
  end

  module Connector
    module Types
      module TimeZoneType
        include IPaaS::Connector::Types::Base

        DEFAULT_TIME_ZONE = 'UTC'.freeze

        ZONES = {
          'international_date_line_west' => 'International Date Line West',
          'midway_island' => 'Midway Island',
          'samoa' => 'Samoa',
          'hawaii' => 'Hawaii',
          'alaska' => 'Alaska',
          'pacific_time' => 'Pacific Time (US & Canada)',
          'tijuana' => 'Tijuana',
          'arizona' => 'Arizona',
          'chihuahua' => 'Chihuahua',
          'mazatlan' => 'Mazatlan',
          'mountain_time' => 'Mountain Time (US & Canada)',
          'central_america' => 'Central America',
          'central_time' => 'Central Time (US & Canada)',
          'guadalajara' => 'Guadalajara',
          'mexico_city' => 'Mexico City',
          'monterrey' => 'Monterrey',
          'saskatchewan' => 'Saskatchewan',
          'bogota' => 'Bogota',
          'eastern_time' => 'Eastern Time (US & Canada)',
          'indiana' => 'Indiana (East)',
          'lima' => 'Lima',
          'quito' => 'Quito',
          'caracas' => 'Caracas',
          'atlantic_time' => 'Atlantic Time (Canada)',
          'la_paz' => 'La Paz',
          'puerto_rico' => 'Puerto Rico',
          'santiago' => 'Santiago',
          'newfoundland' => 'Newfoundland',
          'brasilia' => 'Brasilia',
          'buenos_aires' => 'Buenos Aires',
          'georgetown' => 'Georgetown',
          'greenland' => 'Greenland',
          'mid_atlantic' => 'Mid-Atlantic',
          'azores' => 'Azores',
          'cape_verde_is' => 'Cape Verde Is.',
          'casablanca' => 'Casablanca',
          'dublin' => 'Dublin',
          'edinburgh' => 'Edinburgh',
          'lisbon' => 'Lisbon',
          'london' => 'London',
          'monrovia' => 'Monrovia',
          'utc' => 'UTC',
          'amsterdam' => 'Amsterdam',
          'belgrade' => 'Belgrade',
          'berlin' => 'Berlin',
          'bern' => 'Bern',
          'bratislava' => 'Bratislava',
          'brussels' => 'Brussels',
          'budapest' => 'Budapest',
          'copenhagen' => 'Copenhagen',
          'ljubljana' => 'Ljubljana',
          'madrid' => 'Madrid',
          'paris' => 'Paris',
          'prague' => 'Prague',
          'rome' => 'Rome',
          'sarajevo' => 'Sarajevo',
          'skopje' => 'Skopje',
          'stockholm' => 'Stockholm',
          'vienna' => 'Vienna',
          'warsaw' => 'Warsaw',
          'west_central_africa' => 'West Central Africa',
          'zagreb' => 'Zagreb',
          'zurich' => 'Zurich',
          'athens' => 'Athens',
          'bucharest' => 'Bucharest',
          'cairo' => 'Cairo',
          'harare' => 'Harare',
          'helsinki' => 'Helsinki',
          'istanbul' => 'Istanbul',
          'jerusalem' => 'Jerusalem',
          'kyiv' => 'Kyiv',
          'minsk' => 'Minsk',
          'pretoria' => 'Pretoria',
          'riga' => 'Riga',
          'sofia' => 'Sofia',
          'tallinn' => 'Tallinn',
          'vilnius' => 'Vilnius',
          'baghdad' => 'Baghdad',
          'kuwait' => 'Kuwait',
          'moscow' => 'Moscow',
          'nairobi' => 'Nairobi',
          'riyadh' => 'Riyadh',
          'st_petersburg' => 'St. Petersburg',
          'volgograd' => 'Volgograd',
          'tehran' => 'Tehran',
          'abu_dhabi' => 'Abu Dhabi',
          'baku' => 'Baku',
          'muscat' => 'Muscat',
          'tbilisi' => 'Tbilisi',
          'yerevan' => 'Yerevan',
          'kabul' => 'Kabul',
          'ekaterinburg' => 'Ekaterinburg',
          'islamabad' => 'Islamabad',
          'karachi' => 'Karachi',
          'tashkent' => 'Tashkent',
          'chennai' => 'Chennai',
          'kolkata' => 'Kolkata',
          'mumbai' => 'Mumbai',
          'new_delhi' => 'New Delhi',
          'sri_jayawardenepura' => 'Sri Jayawardenepura',
          'kathmandu' => 'Kathmandu',
          'almaty' => 'Almaty',
          'astana' => 'Astana',
          'dhaka' => 'Dhaka',
          'novosibirsk' => 'Novosibirsk',
          'rangoon' => 'Rangoon',
          'bangkok' => 'Bangkok',
          'hanoi' => 'Hanoi',
          'jakarta' => 'Jakarta',
          'krasnoyarsk' => 'Krasnoyarsk',
          'beijing' => 'Beijing',
          'chongqing' => 'Chongqing',
          'hong_kong' => 'Hong Kong',
          'irkutsk' => 'Irkutsk',
          'kuala_lumpur' => 'Kuala Lumpur',
          'manila' => 'Manila',
          'perth' => 'Perth',
          'singapore' => 'Singapore',
          'taipei' => 'Taipei',
          'ulaan_bataar' => 'Ulaan Bataar',
          'urumqi' => 'Urumqi',
          'osaka' => 'Osaka',
          'sapporo' => 'Sapporo',
          'seoul' => 'Seoul',
          'tokyo' => 'Tokyo',
          'yakutsk' => 'Yakutsk',
          'adelaide' => 'Adelaide',
          'darwin' => 'Darwin',
          'brisbane' => 'Brisbane',
          'canberra' => 'Canberra',
          'guam' => 'Guam',
          'hobart' => 'Hobart',
          'melbourne' => 'Melbourne',
          'port_moresby' => 'Port Moresby',
          'sydney' => 'Sydney',
          'vladivostok' => 'Vladivostok',
          'magadan' => 'Magadan',
          'new_caledonia' => 'New Caledonia',
          'solomon_is' => 'Solomon Is.',
          'auckland' => 'Auckland',
          'fiji' => 'Fiji',
          'kamchatka' => 'Kamchatka',
          'marshall_is' => 'Marshall Is.',
          'wellington' => 'Wellington',
          'nuku_alofa' => "Nuku'alofa",
          'american_samo' => 'American Samoa',
          'montevideo' => 'Montevideo',
          'kaliningrad' => 'Kaliningrad',
          'samara' => 'Samara',
          'ulaanbaatar' => 'Ulaanbaatar',
          'srednekolymsk' => 'Srednekolymsk',
          'chatham_is' => 'Chatham Is.',
          'tokelau_is' => 'Tokelau Is.',
        }.freeze

        ZONES_BY_NAME = ZONES.to_a.to_h(&:reverse).freeze

        class << self
          def ruby_class
            String
          end

          def resolve(resolved_value, context: nil)
            time_zone(resolved_value, fallback: false) || resolved_value
          end

          def valid?(value, _errors = [])
            ZONES.key?(value) || ZONES_BY_NAME.key?(value)
          end

          def example(_field)
            'central_time'
          end

          def time_zone(time_zone, fallback: true)
            return time_zone if ZONES_BY_NAME.key?(time_zone)

            zone = ZONES[time_zone]
            zone ||= DEFAULT_TIME_ZONE if fallback
            zone
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::TimeZoneType)
