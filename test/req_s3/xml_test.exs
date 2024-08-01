defmodule ReqS3.XMLTest do
  use ExUnit.Case, async: true
  doctest ReqS3.XML

  describe "parse_s3" do
    test "ListAllMyBucketsResult" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Owner>
          <ID>7a39</ID>
          <DisplayName>owner</DisplayName>
        </Owner>
        <Buckets>
          <Bucket>
            <Name>bucket1</Name>
            <CreationDate>2023-02-21T15:41:58.000Z</CreationDate>
          </Bucket>
          <Bucket>
            <Name>bucket2</Name>
            <CreationDate>2023-02-21T15:41:58.000Z</CreationDate>
          </Bucket>
        </Buckets>
      </ListAllMyBucketsResult>
      """

      assert ReqS3.XML.parse_s3(xml) == %{
               "ListAllMyBucketsResult" => %{
                 "Buckets" => [
                   %{"CreationDate" => "2023-02-21T15:41:58.000Z", "Name" => "bucket1"},
                   %{"CreationDate" => "2023-02-21T15:41:58.000Z", "Name" => "bucket2"}
                 ],
                 "Owner" => %{"DisplayName" => "owner", "ID" => "7a39"}
               }
             }
    end

    test "ListAllMyBucketsResult single bucket" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Buckets>
          <Bucket>
            <Name>bucket1</Name>
            <CreationDate>2023-02-21T15:41:58.000Z</CreationDate>
          </Bucket>
        </Buckets>
      </ListAllMyBucketsResult>
      """

      assert ReqS3.XML.parse_s3(xml) == %{
               "ListAllMyBucketsResult" => %{
                 "Buckets" => [
                   %{"CreationDate" => "2023-02-21T15:41:58.000Z", "Name" => "bucket1"}
                 ]
               }
             }
    end

    test "ListBucketResult" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Name>ossci-datasets</Name>
        <Prefix></Prefix>
        <Marker></Marker>
        <MaxKeys>1000</MaxKeys>
        <IsTruncated>false</IsTruncated>
        <Contents>
          <Key>mnist/</Key>
          <LastModified>2020-03-04T15:45:17.000Z</LastModified>
          <ETag>&quot;d41d8cd98f00b204e9800998ecf8427e&quot;</ETag>
          <Size>0</Size>
          <StorageClass>STANDARD</StorageClass>
          <Owner><ID></ID></Owner>
        </Contents>
        <Contents>
          <Key>mnist/t10k-images-idx3-ubyte.gz</Key>
          <LastModified>2020-03-04T15:45:52.000Z</LastModified>
          <ETag>&quot;9fb629c4189551a2d022fa330f9573f3&quot;</ETag>
          <Size>1648877</Size>
          <StorageClass>STANDARD</StorageClass>
        </Contents>
      </ListBucketResult>
      """

      assert ReqS3.XML.parse_s3(xml) == %{
               "ListBucketResult" => %{
                 "Contents" => [
                   %{
                     "ETag" => "\"d41d8cd98f00b204e9800998ecf8427e\"",
                     "Key" => "mnist/",
                     "LastModified" => "2020-03-04T15:45:17.000Z",
                     "Size" => "0",
                     "StorageClass" => "STANDARD",
                     "Owner" => %{"ID" => nil}
                   },
                   %{
                     "ETag" => "\"9fb629c4189551a2d022fa330f9573f3\"",
                     "Key" => "mnist/t10k-images-idx3-ubyte.gz",
                     "LastModified" => "2020-03-04T15:45:52.000Z",
                     "Size" => "1648877",
                     "StorageClass" => "STANDARD"
                   }
                 ],
                 "IsTruncated" => "false",
                 "Marker" => nil,
                 "MaxKeys" => "1000",
                 "Name" => "ossci-datasets",
                 "Prefix" => nil
               }
             }
    end

    test "ListBucketResult single object" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Name>ossci-datasets</Name>
        <Contents>
          <Key>mnist/</Key>
          <ETag>&quot;d41d8cd98f00b204e9800998ecf8427e&quot;</ETag>
        </Contents>
      </ListBucketResult>
      """

      assert ReqS3.XML.parse_s3(xml) == %{
               "ListBucketResult" => %{
                 "Contents" => [
                   %{
                     "ETag" => "\"d41d8cd98f00b204e9800998ecf8427e\"",
                     "Key" => "mnist/"
                   }
                 ],
                 "Name" => "ossci-datasets"
               }
             }
    end

    test "ListVersionsResult" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListVersionsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Name>wojtekmach-test</Name>
        <Prefix></Prefix>
        <Version><Key>key1</Key><VersionId>null</VersionId><IsLatest>true</IsLatest><LastModified>2024-03-07T15:07:39.000Z</LastModified></Version>
      </ListVersionsResult>
      """

      assert ReqS3.XML.parse_s3(xml) == %{
               "ListVersionsResult" => %{
                 "Name" => "wojtekmach-test",
                 "Prefix" => nil,
                 "Version" => [
                   %{
                     "IsLatest" => "true",
                     "Key" => "key1",
                     "LastModified" => "2024-03-07T15:07:39.000Z",
                     "VersionId" => "null"
                   }
                 ]
               }
             }
    end
  end

  describe "parse_simple/1" do
    test "it works" do
      xml = """
      <?xml version="1.0"?>
      <root>
        <children>
          <child id="1">Content 1</child>
        </children>
      </root>
      """

      assert ReqS3.XML.parse_simple(xml) ==
               {"root", [], [{"children", [], [{"child", [{"id", "1"}], ["Content 1"]}]}]}
    end

    test "does not leak atoms" do
      uniq = System.unique_integer()

      xml = """
      <?xml version="1.0"?>
      <element#{uniq} attribute#{uniq}=""/>
      """

      assert ReqS3.XML.parse_simple(xml) == {"element#{uniq}", [{"attribute#{uniq}", ""}], []}

      e =
        assert_raise ArgumentError, fn ->
          String.to_existing_atom("element#{uniq}")
        end

      assert e.message =~ "not an already existing atom"

      e =
        assert_raise ArgumentError, fn ->
          String.to_existing_atom("attribute#{uniq}")
        end

      assert e.message =~ "not an already existing atom"
    end
  end
end
