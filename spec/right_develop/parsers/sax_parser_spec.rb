require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper.rb')

describe "xml parser" do
  if RightDevelop::Parsers::SaxParser::AVAILABLE
  it "BaseHelper.xml_post_process_1_5 for root hash formatted xml" do
    expected_hash = {
      "farms"=>[],
      "animals"=>[
        {"species"=>"chicken", "type"=>'bird'},
        {"species"=>"chicken", "type"=>'bird'},
        {"species"=>"horse", "type"=>'mammal'},
        {"species"=>"cow", "type"=>'mammal'},
        {"species"=>"bull", "type"=>'mammal'},
        {"species"=>"rooster", "type"=>'bird'},
        {"species"=>"camel","type"=>'mammal'},
        {"species"=>"sheep", "type"=>'mammal'},
        {"species"=>"wolf", "type"=>'mammal'},
      ]
    }
    session_index_1_5_xml = %@<?xml version="1.0" encoding="UTF-8"?>
      <session>
        <farms></farms>
        <animals>
          <animal species="chicken" type='bird'/>
          <animal species="chicken" type='bird'/>
          <animal species="horse" type='mammal'/>
          <animal species="cow" type='mammal'/>
          <animal species="bull" type='mammal'/>
          <animal species="rooster" type='bird'/>
          <animal species="camel" type='mammal'/>
          <animal species="sheep" type='mammal'/>
          <animal species="wolf" type='mammal'/>
        </animals>
      </session>
    @
    RightDevelop::Parsers::SaxParser.parse(session_index_1_5_xml,
      :post_parser => lambda { |xml| RightDevelop::Parsers::XmlPostParser.remove_nesting(xml) } ).should == expected_hash
  end

  it "BaseHelper.xml_post_process_1_5 for root array formatted xml" do
    expected_array = [
      {
        'farms'=>[{'name'=>'chicken farm'}],
        'farmers'=>[
          {'name'=>'John', 'specialty'=>'harvesting'},
          {'name'=>'Bill', 'specialty'=>'eggs'},
          {'name'=>'Bob',  'specialty'=>'milk'},
          {'name'=>'Joe',  'specialty'=>'butchering'}
        ],
        'description'=>'animal farms',
      },
      {
        'farms'=>[{'name'=>'wheat farm'},{'name'=>'corn farm'}],
        'farmers'=>[
          {'name'=>'May',  'specialty'=>'milling'},
          {'name'=>'Mike', 'specialty'=>'corn'},
          {'name'=>'Will', 'specialty'=>'harvesting'},
          {'name'=>'Moe',  'specialty'=>'sowing'}
        ],
        'description'=>'vegetable farms',
      }
    ]
    servers_index_1_5_xml = %@<?xml version='1.0' encoding='UTF-8'?>
      <farm_clusters>
        <farm_cluster>
          <farms>
            <farm name='chicken farm'/>
          </farms>
          <farmers>
            <farmer name='John' specialty='harvesting'/>
            <farmer name='Bill' specialty='eggs'/>
            <farmer name='Bob'  specialty='milk'/>
            <farmer name='Joe'  specialty='butchering'/>
          </farmers>
          <description>animal farms</description>
        </farm_cluster>
        <farm_cluster>
          <farms>
            <farm name='wheat farm'/>
            <farm name='corn farm'/>
          </farms>
          <farmers>
            <farmer name='May'  specialty='milling'/>
            <farmer name='Mike' specialty='corn'/>
            <farmer name='Will' specialty='harvesting'/>
            <farmer name='Moe'  specialty='sowing'/>
          </farmers>
          <description>vegetable farms</description>
        </farm_cluster>
      </farm_clusters>
    @
    RightDevelop::Parsers::SaxParser.parse(servers_index_1_5_xml,
      :post_parser => lambda { |xml| RightDevelop::Parsers::XmlPostParser.remove_nesting(xml) } ).should == expected_array
  end

  it "BaseHelper.xml_post_process_1_5 for node with empty text string" do
    expected_array = [
      {
        'farms'=>[{'name'=>'server farm'}],
        'description'=>'big time computing'
      },
      {
        'farms'=>[{'name'=>'unlisted farm'}],
        'description'=>nil
      }
    ]
    servers_index_1_5_xml = %@<?xml version='1.0' encoding='UTF-8'?>
      <farm_clusters>
        <farm_cluster>
          <farms>
            <farm name='server farm'/>
          </farms>
          <description>big time computing</description>
        </farm_cluster>
        <farm_cluster>
          <farms>
            <farm name='unlisted farm'/>
          </farms>
          <description></description>
        </farm_cluster>
      </farm_clusters>
    @
    RightDevelop::Parsers::SaxParser.parse(servers_index_1_5_xml,
      :post_parser => lambda { |xml| RightDevelop::Parsers::XmlPostParser.remove_nesting(xml) } ).should == expected_array
  end

  it "BaseHelper.xml_post_process_1_5 custom multiple nested xml" do

    expected_array = [{
        "parents"=>[{
          "children"=> ["Bob", "Mike"]
        }, {
          "children"=> ["Bob", "Mike"]
        }, {
          "children"=> ["Bob", "Mike"]
        }
      ]
      }, {
        "parents"=>[{
            "children"=> ["Bob", "Mike"]
          }, {
            "children"=> ["Bob", "Mike"]
          }, {
            "children"=> ["Bob", "Mike"]
          }
        ]
      }
    ]

    custom_nested_xml = %@<?xml version="1.0" encoding="UTF-8"?>
      <ancestors>
        <ancestor>
          <parents>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
          </parents>
        </ancestor>
        <ancestor>
          <parents>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
            <parent>
              <children>
                <child>Bob</child>
                <child>Mike</child>
              </children>
            </parent>
          </parents>
        </ancestor>
      </ancestors>
    @

    RightDevelop::Parsers::SaxParser.parse(custom_nested_xml,
      :post_parser => lambda { |xml| RightDevelop::Parsers::XmlPostParser.remove_nesting(xml) } ).should == expected_array
  end
  else
    pending 'need to install libxml-ruby and active_support gems in order to run this test'
  end
end