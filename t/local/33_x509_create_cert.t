#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 123;
use Net::SSLeay qw/MBSTRING_ASC MBSTRING_UTF8 EVP_PK_RSA EVP_PKT_SIGN EVP_PKT_ENC/;
use File::Spec;
use utf8;

#use File::Slurp;

Net::SSLeay::randomize();
Net::SSLeay::load_error_strings();
Net::SSLeay::ERR_load_crypto_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();

my $ca_crt_pem = File::Spec->catfile('t', 'data', 'test_CA1.crt.pem');
my $ca_key_pem = File::Spec->catfile('t', 'data', 'test_CA1.key.pem');

ok(my $bio1 = Net::SSLeay::BIO_new_file($ca_crt_pem, 'r'), "BIO_new_file 1");
ok(my $ca_cert = Net::SSLeay::PEM_read_bio_X509($bio1), "PEM_read_bio_X509");
ok(my $bio2 = Net::SSLeay::BIO_new_file($ca_key_pem, 'r'), "BIO_new_file 2");
ok(my $ca_pk = Net::SSLeay::PEM_read_bio_PrivateKey($bio2), "PEM_read_bio_PrivateKey");
is(Net::SSLeay::X509_verify($ca_cert, $ca_pk), 1, "X509_verify");

ok(my $ca_subject = Net::SSLeay::X509_get_subject_name($ca_cert), "X509_get_subject_name");
ok(my $ca_issuer = Net::SSLeay::X509_get_issuer_name($ca_cert), "X509_get_issuer_name");
is(Net::SSLeay::X509_NAME_cmp($ca_issuer, $ca_subject), 0, "X509_NAME_cmp");

{ ### X509 certificate - create directly, sign with $ca_pk
  ok(my $pk  = Net::SSLeay::EVP_PKEY_new(), "EVP_PKEY_new");
  ok(my $rsa = Net::SSLeay::RSA_generate_key(2048, &Net::SSLeay::RSA_F4), "RSA_generate_key");
  ok(Net::SSLeay::EVP_PKEY_assign_RSA($pk,$rsa), "EVP_PKEY_assign_RSA");

  ok(my $x509  = Net::SSLeay::X509_new(), "X509_new");
  ok(Net::SSLeay::X509_set_pubkey($x509,$pk), "X509_set_pubkey");
  ok(my $name = Net::SSLeay::X509_get_subject_name($x509), "X509_get_subject_name");

  ok(Net::SSLeay::X509_NAME_add_entry_by_NID($name, &Net::SSLeay::NID_commonName, MBSTRING_UTF8, "Common name text X509"), "X509_NAME_add_entry_by_NID");
  #set countryName via add_entry_by_OBJ
  ok(my $obj = Net::SSLeay::OBJ_nid2obj(&Net::SSLeay::NID_countryName), "OBJ_nid2obj");
  ok(Net::SSLeay::X509_NAME_add_entry_by_OBJ($name, $obj, MBSTRING_UTF8, "UK"), "X509_NAME_add_entry_by_OBJ");
  #set organizationName via add_entry_by_txt
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "organizationName", MBSTRING_UTF8, "Company Name"), "X509_NAME_add_entry_by_txt");
  
  ok(Net::SSLeay::X509_set_version($x509, 3), "X509_set_version");
  ok(my $sn = Net::SSLeay::X509_get_serialNumber($x509), "X509_get_serialNumber");
  
  ##let us do some ASN1_INTEGER related testing
  #test big integer via P_ASN1_INTEGER_set_dec
  Net::SSLeay::P_ASN1_INTEGER_set_dec($sn, '123456789123456789123456789123456789123456789');
  # On platforms with 64-bit long int returns 4294967295 rather than -1
  my $asn1_integer = Net::SSLeay::ASN1_INTEGER_get(Net::SSLeay::X509_get_serialNumber($x509));
  if ($asn1_integer == 4294967295) {
    $asn1_integer = -1;
  }
  is($asn1_integer, -1, "ASN1_INTEGER_get");
  is(Net::SSLeay::P_ASN1_INTEGER_get_hex(Net::SSLeay::X509_get_serialNumber($x509)), '058936E53D139AFEFABB2683F150B684045F15', "P_ASN1_INTEGER_get_hex");
  #test short integer via P_ASN1_INTEGER_set_hex
  Net::SSLeay::P_ASN1_INTEGER_set_hex($sn, 'D05F14');    
  is(Net::SSLeay::ASN1_INTEGER_get(Net::SSLeay::X509_get_serialNumber($x509)), 13655828, "ASN1_INTEGER_get");
  is(Net::SSLeay::P_ASN1_INTEGER_get_dec(Net::SSLeay::X509_get_serialNumber($x509)), '13655828', "P_ASN1_INTEGER_get_dec");
  #test short integer via ASN1_INTEGER_set
  Net::SSLeay::ASN1_INTEGER_set($sn, 123456);    
  is(Net::SSLeay::P_ASN1_INTEGER_get_hex(Net::SSLeay::X509_get_serialNumber($x509)), '01E240', "P_ASN1_INTEGER_get_hex");
  
  Net::SSLeay::X509_set_issuer_name($x509, Net::SSLeay::X509_get_subject_name($ca_cert));
  SKIP: {
    skip 'openssl-0.9.7e required', 2 unless Net::SSLeay::SSLeay >= 0x0090705f; 
    ok(Net::SSLeay::P_ASN1_TIME_set_isotime(Net::SSLeay::X509_get_notBefore($x509), "2010-02-01T00:00:00Z"), "P_ASN1_TIME_set_isotime+X509_get_notBefore");
    ok(Net::SSLeay::P_ASN1_TIME_set_isotime(Net::SSLeay::X509_get_notAfter($x509), "2099-02-01T00:00:00Z"), "P_ASN1_TIME_set_isotime+X509_get_notAfter");
  }
  
  ok(Net::SSLeay::P_X509_add_extensions($x509,$ca_cert,
        &Net::SSLeay::NID_key_usage => 'digitalSignature,keyEncipherment',
        &Net::SSLeay::NID_basic_constraints => 'CA:FALSE',
        &Net::SSLeay::NID_ext_key_usage => 'serverAuth,clientAuth',
        &Net::SSLeay::NID_netscape_cert_type => 'server',
        &Net::SSLeay::NID_subject_alt_name => 'DNS:s1.dom.com,DNS:s2.dom.com,DNS:s3.dom.com',
        &Net::SSLeay::NID_crl_distribution_points => 'URI:http://pki.dom.com/crl1.pem,URI:http://pki.dom.com/crl2.pem',
    ), "P_X509_add_extensions");

  ok(my $sha1_digest = Net::SSLeay::EVP_get_digestbyname("sha1"), "EVP_get_digestbyname");
  ok(Net::SSLeay::X509_sign($x509, $ca_pk, $sha1_digest), "X509_sign");
  
  is(Net::SSLeay::X509_get_version($x509), 3, "X509_get_version");  
  is(Net::SSLeay::X509_verify($x509, Net::SSLeay::X509_get_pubkey($ca_cert)), 1, "X509_verify");
  
  like(my $crt_pem = Net::SSLeay::PEM_get_string_X509($x509), qr/-----BEGIN CERTIFICATE-----/, "PEM_get_string_X509");
  
  like(my $key_pem1 = Net::SSLeay::PEM_get_string_PrivateKey($pk), qr/-----BEGIN (RSA )?PRIVATE KEY-----/, "PEM_get_string_PrivateKey+nopasswd");        
  like(my $key_pem2 = Net::SSLeay::PEM_get_string_PrivateKey($pk,"password"), qr/-----BEGIN (ENCRYPTED|RSA) PRIVATE KEY-----/, "PEM_get_string_PrivateKey+passwd");
  
  Net::SSLeay::OpenSSL_add_all_algorithms();
  if (Net::SSLeay::SSLeay >= 0x0090700f) {
    #just test whether we can call the following functions
    Net::SSLeay::OPENSSL_add_all_algorithms_conf();
    Net::SSLeay::OPENSSL_add_all_algorithms_noconf();
  }
  ok(my $alg1 = Net::SSLeay::EVP_get_cipherbyname("DES-EDE3-CBC"), "EVP_get_cipherbyname");
  like(my $key_pem3 = Net::SSLeay::PEM_get_string_PrivateKey($pk,"password",$alg1), qr/-----BEGIN (ENCRYPTED|RSA) PRIVATE KEY-----/, "PEM_get_string_PrivateKey+passwd+enc_alg");
  
  ok(my $alg2 = Net::SSLeay::EVP_get_cipherbyname("DES-EDE3-OFB"), "EVP_get_cipherbyname");
  like(my $key_pem4 = Net::SSLeay::PEM_get_string_PrivateKey($pk,"password",$alg2), qr/-----BEGIN (ENCRYPTED|RSA) PRIVATE KEY-----/, "PEM_get_string_PrivateKey+passwd+enc_alg");
  
  is(Net::SSLeay::X509_NAME_print_ex($name), "O=Company Name,C=UK,CN=Common name text X509", "X509_NAME_print_ex");  

  # 2014-06-06: Sigh, some versions of openssl have this patch, which afffects the results of this test:
  # https://git.openssl.org/gitweb/?p=openssl.git;a=commit;h=3009244da47b989c4cc59ba02cf81a4e9d8f8431
  # with this patch, the result is "ce83889f1beab8e70aa142e07e94b0ebbd9d59e0"
#  is(unpack("H*",Net::SSLeay::X509_NAME_digest($name, $sha1_digest)), "044d7ea7fddced7b9b63799600b9989a63b36819", "X509_NAME_digest");
  
  ok(my $ext_idx = Net::SSLeay::X509_get_ext_by_NID($x509, &Net::SSLeay::NID_ext_key_usage), "X509_get_ext_by_NID");
  ok(my $ext = Net::SSLeay::X509_get_ext($x509, $ext_idx), "X509_get_ext");
  is(Net::SSLeay::X509V3_EXT_print($ext), 'TLS Web Server Authentication, TLS Web Client Authentication', "X509V3_EXT_print");
  
  #write_file("tmp_cert1.crt.pem", $crt_pem);
  #write_file("tmp_cert1.key1.pem", $key_pem1);
  #write_file("tmp_cert1.key2.pem", $key_pem2);
  #write_file("tmp_cert1.key3.pem", $key_pem3);
  #write_file("tmp_cert1.key4.pem", $key_pem4);
}

{ ### X509_REQ certificate request >> sign >> X509 certificate
  
  ## PHASE1 - create certificate request
  ok(my $pk  = Net::SSLeay::EVP_PKEY_new(), "EVP_PKEY_new");
  ok(my $rsa = Net::SSLeay::RSA_generate_key(2048, &Net::SSLeay::RSA_F4), "RSA_generate_key");
  ok(Net::SSLeay::EVP_PKEY_assign_RSA($pk,$rsa), "EVP_PKEY_assign_RSA");

  ok(my $req  = Net::SSLeay::X509_REQ_new(), "X509_REQ_new");
  ok(Net::SSLeay::X509_REQ_set_pubkey($req,$pk), "X509_REQ_set_pubkey");
  ok(my $name = Net::SSLeay::X509_REQ_get_subject_name($req), "X509_REQ_get_subject_name");
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "commonName", MBSTRING_UTF8, "Common name text X509_REQ"), "X509_NAME_add_entry_by_txt");
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "countryName", MBSTRING_UTF8, "UK"), "X509_NAME_add_entry_by_txt");
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "organizationName", MBSTRING_UTF8, "Company Name"), "X509_NAME_add_entry_by_txt");
  
  ok(Net::SSLeay::P_X509_REQ_add_extensions($req,
        &Net::SSLeay::NID_key_usage => 'digitalSignature,keyEncipherment',
        &Net::SSLeay::NID_basic_constraints => 'CA:FALSE',
        &Net::SSLeay::NID_ext_key_usage => 'serverAuth,clientAuth',
        &Net::SSLeay::NID_netscape_cert_type => 'server',
        &Net::SSLeay::NID_subject_alt_name => 'DNS:s1.com,DNS:s2.com',
        &Net::SSLeay::NID_crl_distribution_points => 'URI:http://pki.com/crl1,URI:http://pki.com/crl2',        
    ), "P_X509_REQ_add_extensions");
  
  #54 = NID_pkcs9_challengePassword - XXX-TODO add new constant
  ok(Net::SSLeay::X509_REQ_add1_attr_by_NID($req, 54, MBSTRING_ASC, 'password xyz'), "X509_REQ_add1_attr_by_NID");
  #49 = NID_pkcs9_unstructuredName - XXX-TODO add new constant
  ok(Net::SSLeay::X509_REQ_add1_attr_by_NID($req, 49, MBSTRING_ASC, 'Any Uns.name'), "X509_REQ_add1_attr_by_NID");
   
  ok(Net::SSLeay::X509_REQ_set_version($req, 2), "X509_REQ_set_version");

  ok(my $sha1_digest = Net::SSLeay::EVP_get_digestbyname("sha1"), "EVP_get_digestbyname");
  ok(Net::SSLeay::X509_REQ_sign($req, $pk, $sha1_digest), "X509_REQ_sign");
  
  ok(my $req_pubkey = Net::SSLeay::X509_REQ_get_pubkey($req), "X509_REQ_get_pubkey");
  is(Net::SSLeay::X509_REQ_verify($req, $req_pubkey), 1, "X509_REQ_verify");
  
  is(Net::SSLeay::X509_REQ_get_version($req), 2, "X509_REQ_get_version");
  ok(my $obj_challengePassword = Net::SSLeay::OBJ_txt2obj('1.2.840.113549.1.9.7'), "OBJ_txt2obj");
  ok(my $nid_challengePassword = Net::SSLeay::OBJ_obj2nid($obj_challengePassword), "OBJ_obj2nid");  
  is(Net::SSLeay::X509_REQ_get_attr_count($req), 3, "X509_REQ_get_attr_count");
  is(my $n1 = Net::SSLeay::X509_REQ_get_attr_by_NID($req, $nid_challengePassword,-1), 1, "X509_REQ_get_attr_by_NID");
  is(my $n2 = Net::SSLeay::X509_REQ_get_attr_by_OBJ($req, $obj_challengePassword,-1), 1, "X509_REQ_get_attr_by_OBJ");
  
  SKIP: {
    skip('requires openssl-0.9.7', 3) unless Net::SSLeay::SSLeay >= 0x0090700f;
    ok(my @attr_values = Net::SSLeay::P_X509_REQ_get_attr($req, $n1), "P_X509_REQ_get_attr");
    is(scalar(@attr_values), 1, "attr_values size");
    is(Net::SSLeay::P_ASN1_STRING_get($attr_values[0]), "password xyz", "attr_values[0]");
  }
  
  like(my $req_pem = Net::SSLeay::PEM_get_string_X509_REQ($req), qr/-----BEGIN CERTIFICATE REQUEST-----/, "PEM_get_string_X509_REQ");
  like(my $key_pem = Net::SSLeay::PEM_get_string_PrivateKey($pk), qr/-----BEGIN (RSA )?PRIVATE KEY-----/, "PEM_get_string_PrivateKey");  
  
  #write_file("tmp_cert2.req.pem", $req_pem);
  #write_file("tmp_cert2.key.pem", $key_pem);
  
  ## PHASE2 - turn X509_REQ into X509 cert + sign with CA key
  ok(my $x509ss = Net::SSLeay::X509_new(), "X509_new");
  ok(Net::SSLeay::X509_set_version($x509ss, 2), "X509_set_version");
  ok(my $sn = Net::SSLeay::X509_get_serialNumber($x509ss), "X509_get_serialNumber");
  Net::SSLeay::P_ASN1_INTEGER_set_hex($sn, 'ABCDEF');
  Net::SSLeay::X509_set_issuer_name($x509ss, Net::SSLeay::X509_get_subject_name($ca_cert));
  ok(Net::SSLeay::X509_gmtime_adj(Net::SSLeay::X509_get_notBefore($x509ss), 0), "X509_gmtime_adj + X509_get_notBefore");
  ok(Net::SSLeay::X509_gmtime_adj(Net::SSLeay::X509_get_notAfter($x509ss), 60*60*24*100), "X509_gmtime_adj + X509_get_notAfter");
  ok(Net::SSLeay::X509_set_subject_name($x509ss, Net::SSLeay::X509_REQ_get_subject_name($req)), "X509_set_subject_name + X509_REQ_get_subject_name");
  
  ok(Net::SSLeay::P_X509_copy_extensions($req, $x509ss), "P_X509_copy_extensions");
    
  ok(my $tmppkey = Net::SSLeay::X509_REQ_get_pubkey($req), "X509_REQ_get_pubkey");
  ok(Net::SSLeay::X509_set_pubkey($x509ss,$tmppkey), "X509_set_pubkey");
  Net::SSLeay::EVP_PKEY_free($tmppkey);
  
  ok(Net::SSLeay::X509_sign($x509ss, $ca_pk, $sha1_digest), "X509_sign");
  like(my $crt_pem = Net::SSLeay::PEM_get_string_X509($x509ss), qr/-----BEGIN CERTIFICATE-----/, "PEM_get_string_X509");

  #write_file("tmp_cert2.crt.pem", $crt_pem);

  ## PHASE3 - check some certificate parameters
  is(Net::SSLeay::X509_NAME_print_ex(Net::SSLeay::X509_get_subject_name($x509ss)), "O=Company Name,C=UK,CN=Common name text X509_REQ", "X509_NAME_print_ex 1");
  is(Net::SSLeay::X509_NAME_print_ex(Net::SSLeay::X509_get_issuer_name($x509ss)), "CN=CA1,O=Demo1,C=US", "X509_NAME_print_ex 2");
  SKIP: {
    skip 'openssl-0.9.7e required', 2 unless Net::SSLeay::SSLeay >= 0x0090705f; 
    like(Net::SSLeay::P_ASN1_TIME_get_isotime(Net::SSLeay::X509_get_notBefore($x509ss)), qr/^\d\d\d\d-\d\d-\d\d/, "X509_get_notBefore");
    like(Net::SSLeay::P_ASN1_TIME_get_isotime(Net::SSLeay::X509_get_notAfter($x509ss)), qr/^\d\d\d\d-\d\d-\d\d/, "X509_get_notAfter");
  }
  
  my $mask = EVP_PK_RSA | EVP_PKT_SIGN | EVP_PKT_ENC;
  is(Net::SSLeay::X509_certificate_type($x509ss)&$mask, $mask, "X509_certificate_type");
 
  is(Net::SSLeay::X509_REQ_free($req), undef, "X509_REQ_free");
  is(Net::SSLeay::X509_free($x509ss), undef, "X509_free");
}

SKIP: { ### X509 certificate - unicode
  skip('skiiping unicode related stuff on perl 5.6', 5) if $] < 5.007;
  ok(my $x509  = Net::SSLeay::X509_new(), "X509_new");
  ok(my $name = Net::SSLeay::X509_get_subject_name($x509), "X509_get_subject_name");
  my $txt = "\x{17E}lut\xFD";
  utf8::encode($txt);
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "CN", MBSTRING_UTF8, $txt), "X509_NAME_add_entry_by_txt");
  ok(Net::SSLeay::X509_NAME_add_entry_by_txt($name, "OU", MBSTRING_UTF8, "Unit"), "X509_NAME_add_entry_by_txt");  
  is(Net::SSLeay::X509_NAME_print_ex($name), 'OU=Unit,CN=\C5\BElut\C3\BD', "X509_NAME_print_ex");
}

{ ### X509 certificate - copy some fields from other certificate

  my $orig_crt_pem = File::Spec->catfile('t', 'data', 'cert_twitter.crt.pem');
  ok(my $bio = Net::SSLeay::BIO_new_file($orig_crt_pem, 'r'), "BIO_new_file");
  ok(my $orig_cert = Net::SSLeay::PEM_read_bio_X509($bio), "PEM_read_bio_X509");

  ok(my $pk  = Net::SSLeay::EVP_PKEY_new(), "EVP_PKEY_new");
  ok(my $rsa = Net::SSLeay::RSA_generate_key(2048, &Net::SSLeay::RSA_F4), "RSA_generate_key");
  ok(Net::SSLeay::EVP_PKEY_assign_RSA($pk,$rsa), "EVP_PKEY_assign_RSA");

  ok(my $x509  = Net::SSLeay::X509_new(), "X509_new");
  ok(Net::SSLeay::X509_set_pubkey($x509,$pk), "X509_set_pubkey");
  ok(my $name = Net::SSLeay::X509_get_subject_name($orig_cert), "X509_get_subject_name");
  ok(Net::SSLeay::X509_set_subject_name($x509, $name), "X509_set_subject_name");
  
  ok(my $sn = Net::SSLeay::X509_get_serialNumber($orig_cert), "X509_get_serialNumber");
  ok(Net::SSLeay::X509_set_serialNumber($x509, $sn), "X509_get_serialNumber");

  Net::SSLeay::X509_set_issuer_name($x509, Net::SSLeay::X509_get_subject_name($ca_cert));
  SKIP: {
    skip 'openssl-0.9.7e required', 2 unless Net::SSLeay::SSLeay >= 0x0090705f;
    ok(Net::SSLeay::P_ASN1_TIME_set_isotime(Net::SSLeay::X509_get_notBefore($x509), "2010-02-01T00:00:00Z") , "P_ASN1_TIME_set_isotime+X509_get_notBefore");
    ok(Net::SSLeay::P_ASN1_TIME_set_isotime(Net::SSLeay::X509_get_notAfter($x509), "2099-02-01T00:00:00Z"), "P_ASN1_TIME_set_isotime+X509_get_notAfter");
  }
  
  ok(my $sha1_digest = Net::SSLeay::EVP_get_digestbyname("sha1"), "EVP_get_digestbyname");
  ok(Net::SSLeay::X509_sign($x509, $ca_pk, $sha1_digest), "X509_sign");
  
  like(my $crt_pem = Net::SSLeay::PEM_get_string_X509($x509), qr/-----BEGIN CERTIFICATE-----/, "PEM_get_string_X509");
  like(my $key_pem = Net::SSLeay::PEM_get_string_PrivateKey($pk), qr/-----BEGIN (RSA )?PRIVATE KEY-----/, "PEM_get_string_PrivateKey");  
    
  #write_file("tmp_cert3.crt.pem", $crt_pem);
  #write_file("tmp_cert3.key.pem", $key_pem);
}

{ ### X509 request from file + some special tests
  my $req_pem = File::Spec->catfile('t', 'data', 'testreq1.pem');
  ok(my $bio = Net::SSLeay::BIO_new_file($req_pem, 'r'), "BIO_new_file");
  ok(my $req = Net::SSLeay::PEM_read_bio_X509_REQ($bio), "PEM_read_bio_X509");
  
  ok(my $sha1_digest = Net::SSLeay::EVP_get_digestbyname("sha1"), "EVP_get_digestbyname");
  is(unpack("H*", Net::SSLeay::X509_REQ_digest($req, $sha1_digest)), "1eda97a279f2bb518f96d1690aa9342c72d1c4ee", "X509_REQ_digest");
  
  ok(my $req2  = Net::SSLeay::X509_REQ_new(), "X509_REQ_new");  
  ok(my $name = Net::SSLeay::X509_REQ_get_subject_name($req), "X509_REQ_get_subject_name");
  ok(Net::SSLeay::X509_REQ_set_subject_name($req2, $name), "X509_REQ_set_subject_name");
  is(Net::SSLeay::X509_REQ_free($req), undef, "X509_REQ_free");     
}

{ ### X509 + X509_REQ loading DER format
  my $req_der = File::Spec->catfile('t', 'data', 'testreq1.der');
  ok(my $bio1 = Net::SSLeay::BIO_new_file($req_der, 'r'), "BIO_new_file");
  ok(my $req = Net::SSLeay::d2i_X509_REQ_bio($bio1), "d2i_X509_REQ_bio");
  
  my $x509_der = File::Spec->catfile('t', 'data', 'testcert_simple.crt.der');
  ok(my $bio2 = Net::SSLeay::BIO_new_file($x509_der, 'r'), "BIO_new_file");
  ok(my $x509 = Net::SSLeay::d2i_X509_bio($bio2), "d2i_X509_bio");
}
