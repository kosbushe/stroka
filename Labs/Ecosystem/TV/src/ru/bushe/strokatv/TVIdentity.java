package ru.bushe.strokatv.lab;

import android.content.Context;
import android.security.keystore.*;
import javax.net.ssl.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import javax.security.auth.x500.X500Principal;
import java.security.*;
import java.security.spec.ECGenParameterSpec;
import java.math.BigInteger;
import java.util.*;
import android.util.Base64;

final class TVIdentity {
    final KeyStore store;
    final String id, fingerprint;
    final SSLContext tls;
    volatile String requestedKeyType="";
    TVIdentity(Context context)throws Exception {
        store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        if(!store.containsAlias("stroka-tv-tls-v2a")){
            KeyPairGenerator gen=KeyPairGenerator.getInstance("EC","AndroidKeyStore");
            gen.initialize(new KeyGenParameterSpec.Builder("stroka-tv-tls-v2a",KeyProperties.PURPOSE_SIGN|KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_NONE,KeyProperties.DIGEST_SHA256)
                .setCertificateSubject(new X500Principal("CN=Stroka TV local identity"))
                .setCertificateSerialNumber(new BigInteger(128,new SecureRandom()))
                .setCertificateNotBefore(new Date(System.currentTimeMillis()-86400000L))
                .setCertificateNotAfter(new Date(System.currentTimeMillis()+10L*365*86400000L)).build());gen.generateKeyPair();
        }
        byte[] cert=store.getCertificate("stroka-tv-tls-v2a").getEncoded();fingerprint=hex(MessageDigest.getInstance("SHA-256").digest(cert));id=fingerprint.substring(0,16);
        // AndroidKeyStore private keys are deliberately non-exportable. Serve the key by alias.
        X509ExtendedKeyManager manager=new X509ExtendedKeyManager(){
            public String[] getClientAliases(String type,java.security.Principal[] issuers){return null;}
            public String chooseClientAlias(String[] types,java.security.Principal[] issuers,java.net.Socket socket){return null;}
            public String[] getServerAliases(String type,java.security.Principal[] issuers){return "EC".equals(type)?new String[]{"tv"}:null;}
            public String chooseServerAlias(String type,java.security.Principal[] issuers,java.net.Socket socket){requestedKeyType=type;return ("EC".equals(type)||"EC_EC".equals(type))?"tv":null;}
            public String chooseEngineServerAlias(String type,java.security.Principal[] issuers,SSLEngine engine){return "EC".equals(type)?"tv":null;}
            public java.security.cert.X509Certificate[] getCertificateChain(String alias){try{return new java.security.cert.X509Certificate[]{(java.security.cert.X509Certificate)store.getCertificate("stroka-tv-tls-v2a")};}catch(Exception e){return null;}}
            public PrivateKey getPrivateKey(String alias){try{return (PrivateKey)store.getKey("stroka-tv-tls-v2a",null);}catch(Exception e){return null;}}
        };
        tls=SSLContext.getInstance("TLS");tls.init(new KeyManager[]{manager},null,new SecureRandom());
        if(!store.containsAlias("stroka-controller-v2")){
            KeyGenerator gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
            gen.init(new KeyGenParameterSpec.Builder("stroka-controller-v2",KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());gen.generateKey();
        }
    }
    String seal(String value)throws Exception {
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,store.getKey("stroka-controller-v2",null));
        return Base64.encodeToString(c.getIV(),Base64.NO_WRAP)+":"+Base64.encodeToString(c.doFinal(value.getBytes("UTF-8")),Base64.NO_WRAP);
    }
    String open(String value)throws Exception {
        String[] p=value.split(":");if(p.length!=2)throw new Exception("Invalid sealed value");
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,store.getKey("stroka-controller-v2",null),new GCMParameterSpec(128,Base64.decode(p[0],Base64.NO_WRAP)));
        return new String(c.doFinal(Base64.decode(p[1],Base64.NO_WRAP)),"UTF-8");
    }
    static String random(){byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);return hex(bytes);}
    static String hex(byte[] bytes){StringBuilder b=new StringBuilder();for(byte x:bytes)b.append(String.format(Locale.ROOT,"%02x",x&255));return b.toString();}
}
