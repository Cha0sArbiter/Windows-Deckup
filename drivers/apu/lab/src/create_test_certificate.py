"""Create a local signing certificate without changing Windows trust stores."""
import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import secrets

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory")
    parser.add_argument("--common-name", default="Steam Deck LCD Driver Lab Test")
    args = parser.parse_args()
    output = Path(args.directory)
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in ["DeckLCD-Test.cer", "DeckLCD-Test.pfx", "signing.password"]):
        raise SystemExit("Certificate files already exist; refusing to replace them")
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, args.common_name)])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=5)).not_valid_after(now + timedelta(days=1825))
                   .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                   .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                                               key_encipherment=False, data_encipherment=False,
                                               key_agreement=False, key_cert_sign=False, crl_sign=False,
                                               encipher_only=None, decipher_only=None), critical=True)
                   .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]), critical=False)
                   .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
                   .sign(key, hashes.SHA256()))
    password = secrets.token_urlsafe(32)
    (output / "DeckLCD-Test.cer").write_bytes(certificate.public_bytes(serialization.Encoding.DER))
    (output / "DeckLCD-Test.pfx").write_bytes(pkcs12.serialize_key_and_certificates(
        args.common_name.encode("utf-8"), key, certificate, None,
        serialization.BestAvailableEncryption(password.encode("ascii"))))
    (output / "signing.password").write_text(password, encoding="ascii")
    print("Created a local test certificate; Windows trust stores are unchanged.")
