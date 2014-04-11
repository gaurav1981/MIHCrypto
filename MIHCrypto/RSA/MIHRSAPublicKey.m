//
// Created by Michael Hohl on 23.03.14.
// Copyright (c) 2014 Michael Hohl. All rights reserved.
//

#import "MIHRSAPublicKey.h"
#import "MIHInternal.h"
#include <openssl/pem.h>

@implementation MIHRSAPublicKey

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, NSCoding and NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithData:(NSData *)dataValue
{
    NSParameterAssert([dataValue isKindOfClass:[NSData class]]);
    self = [super init];
    if (self) {
        // --- BEGIN OPENSSL HACK ---
        NSString *base64DataString = [dataValue base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        base64DataString = [@"-----BEGIN PUBLIC KEY-----\n" stringByAppendingString:base64DataString];
        base64DataString = [base64DataString stringByAppendingString:@"\n-----END PUBLIC KEY-----"];
        NSData *base64Data = [base64DataString dataUsingEncoding:NSUTF8StringEncoding];
        // --- END OPENSSL HACK ---

        BIO *publicBIO = BIO_new_mem_buf((void *) base64Data.bytes, base64Data.length);
        EVP_PKEY *pkey = EVP_PKEY_new();
        @try {
            if (!PEM_read_bio_PUBKEY(publicBIO, &pkey, NULL, NULL)) {
                @throw [NSException openSSLException];
            }
            _rsa = EVP_PKEY_get1_RSA(pkey);
        }
        @finally {
            //EVP_PKEY_free(pkey);
        }
    }

    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    NSData *dataValue = [coder decodeObjectForKey:@"dataValue"];
    return [self initWithData:dataValue];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.dataValue forKey:@"dataValue"];
}

- (id)copyWithZone:(NSZone *)zone
{
    MIHRSAPublicKey *copy = [[[self class] allocWithZone:zone] init];

    if (copy != nil) {
        CRYPTO_add(&_rsa->references, 1, CRYPTO_LOCK_RSA);
        copy->_rsa = _rsa;
    }

    return copy;
}

- (void)dealloc
{
    RSA_free(_rsa);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark MIHPublicKey
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)dataValue
{
    // OpenSSL PEM Writer requires the key in EVP_PKEY format:
    EVP_PKEY *pkey = EVP_PKEY_new();
    char *publicBytes;
    size_t publicBytesLength;
    @try {
        EVP_PKEY_set1_RSA(pkey, _rsa);

        BIO *publicBIO = BIO_new(BIO_s_mem());
        PEM_write_bio_PUBKEY(publicBIO, pkey);
        publicBytesLength = (size_t) BIO_pending(publicBIO);
        publicBytes = malloc(publicBytesLength);
        BIO_read(publicBIO, publicBytes, publicBytesLength);
    }
    @finally {
        EVP_PKEY_free(pkey);
    }

    // --- BEGIN OPENSSL HACK ---
    NSData *rawDataValue = [NSData dataWithBytesNoCopy:publicBytes length:publicBytesLength];
    NSMutableString *dataString = [[NSMutableString alloc] initWithData:rawDataValue encoding:NSUTF8StringEncoding];
    // Remove: '-----BEGIN RSA PUBLIC KEY-----' or '-----END RSA PUBLIC KEY-----'
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(-{5,}BEGIN (RSA )?PUBLIC KEY-{5,})|(-{5,}END (RSA )?PUBLIC KEY-{5,})|\n"
                                                                           options:0
                                                                             error:nil];
    [regex replaceMatchesInString:dataString
                          options:0
                            range:NSMakeRange(0, dataString.length)
                     withTemplate:@""];
    // --- END OPENSSL HACK ---

    return [[NSData alloc] initWithBase64EncodedString:dataString options:0];
}

- (NSData *)encrypt:(NSData *)messageData error:(NSError **)error
{
    NSMutableData *cipherData = [NSMutableData dataWithLength:(NSUInteger) RSA_size(_rsa)];
    int cipherBytesLength = RSA_public_encrypt(messageData.length, messageData.bytes, cipherData.mutableBytes, _rsa, RSA_PKCS1_OAEP_PADDING);
    if (cipherBytesLength < 0) {
        *error = [NSError errorFromOpenSSL];
    }
    [cipherData setLength:(NSUInteger) cipherBytesLength];

    return cipherData;
}

- (BOOL)verifySignatureWithSHA256:(NSData *)signature message:(NSData *)message
{
    SHA256_CTX sha256Ctx;
    unsigned char messageDigest[SHA256_DIGEST_LENGTH];
    if(!SHA256_Init(&sha256Ctx)) {
        return NO;
    }
    if (!SHA256_Update(&sha256Ctx, message.bytes, message.length)) {
        return NO;
    }
    if (!SHA256_Final(messageDigest, &sha256Ctx)) {
        return NO;
    }
    if (RSA_verify(NID_sha256, messageDigest, SHA256_DIGEST_LENGTH, signature.bytes, signature.length, _rsa) == 0) {
        return NO;
    }
    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSObject
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
    return [[NSString alloc] initWithData:[self dataValue] encoding:NSUTF8StringEncoding];
}

@end