package main

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestNormalizeAccessTeamDomain(t *testing.T) {
	valid, err := normalizeAccessTeamDomain("https://equipe.cloudflareaccess.com/")
	if err != nil || valid != "https://equipe.cloudflareaccess.com" {
		t.Fatalf("domínio oficial recusado: %q %v", valid, err)
	}
	for _, value := range []string{
		"http://equipe.cloudflareaccess.com",
		"https://cloudflareaccess.com.evil.example",
		"https://equipe.cloudflareaccess.com/path",
		"https://user@equipe.cloudflareaccess.com",
	} {
		if _, err := normalizeAccessTeamDomain(value); err == nil {
			t.Fatalf("domínio inseguro aceito: %q", value)
		}
	}
}

func TestAccessVerifierAcceptsOnlyBoundIdentity(t *testing.T) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	const keyID = "setupmno-test-key"
	var requests atomic.Int32
	jwks := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]any{{
			"kid": keyID,
			"kty": "RSA",
			"alg": "RS256",
			"use": "sig",
			"n":   base64.RawURLEncoding.EncodeToString(privateKey.PublicKey.N.Bytes()),
			"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(privateKey.PublicKey.E)).Bytes()),
		}}})
	}))
	defer jwks.Close()

	verifier, err := newAccessVerifier(
		true,
		"https://setupmno.cloudflareaccess.com",
		"audiencia-segura-setupmno-1234567890",
		"admin@example.com",
		jwks.Client(),
	)
	if err != nil {
		t.Fatal(err)
	}
	verifier.certsURL = jwks.URL
	verifier.now = func() time.Time { return time.Unix(2_000_000_000, 0) }

	claims := map[string]any{
		"iss":   verifier.issuer,
		"aud":   []string{"outro", verifier.audience},
		"sub":   "identity-123",
		"email": "Admin@Example.com",
		"iat":   verifier.now().Add(-time.Minute).Unix(),
		"nbf":   verifier.now().Add(-time.Minute).Unix(),
		"exp":   verifier.now().Add(time.Hour).Unix(),
	}
	token := signedAccessToken(t, privateKey, keyID, claims)
	identity, err := verifier.verify(context.Background(), token)
	if err != nil {
		t.Fatalf("JWT válido recusado: %v", err)
	}
	if identity.Subject != "identity-123" || identity.Email != "admin@example.com" {
		t.Fatalf("identidade inesperada: %#v", identity)
	}
	if _, err := verifier.verify(context.Background(), token); err != nil {
		t.Fatalf("JWT válido recusado pelo cache: %v", err)
	}
	if requests.Load() != 1 {
		t.Fatalf("cache JWKS não foi usado: %d consultas", requests.Load())
	}

	for name, mutate := range map[string]func(map[string]any){
		"audiencia": func(value map[string]any) { value["aud"] = "outra-audiencia" },
		"email":     func(value map[string]any) { value["email"] = "intruso@example.com" },
		"expirado":  func(value map[string]any) { value["exp"] = verifier.now().Add(-2 * time.Minute).Unix() },
		"futuro":    func(value map[string]any) { value["nbf"] = verifier.now().Add(2 * time.Minute).Unix() },
	} {
		t.Run(name, func(t *testing.T) {
			changed := make(map[string]any, len(claims))
			for key, value := range claims {
				changed[key] = value
			}
			mutate(changed)
			if _, err := verifier.verify(context.Background(), signedAccessToken(t, privateKey, keyID, changed)); err == nil {
				t.Fatal("JWT inseguro foi aceito")
			}
		})
	}

	tampered := strings.Split(token, ".")
	tampered[1] = base64.RawURLEncoding.EncodeToString([]byte(`{"iss":"https://setupmno.cloudflareaccess.com","aud":"audiencia-segura-setupmno-1234567890","sub":"identity-123","email":"admin@example.com","exp":2000003600}`))
	if _, err := verifier.verify(context.Background(), strings.Join(tampered, ".")); err == nil {
		t.Fatal("assinatura adulterada foi aceita")
	}
}

func TestAccessMiddlewareAllowsOnlyInternalHealthWithoutJWT(t *testing.T) {
	verifier := &accessVerifier{required: true}
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	handler := verifier.middleware(next)

	health := httptest.NewRecorder()
	handler.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/health", nil))
	if health.Code != http.StatusNoContent {
		t.Fatalf("healthcheck interno bloqueado: %d", health.Code)
	}

	protected := httptest.NewRecorder()
	handler.ServeHTTP(protected, httptest.NewRequest(http.MethodGet, "/", nil))
	if protected.Code != http.StatusUnauthorized {
		t.Fatalf("rota sem JWT não foi bloqueada: %d", protected.Code)
	}
}

func signedAccessToken(t *testing.T, privateKey *rsa.PrivateKey, keyID string, claims map[string]any) string {
	t.Helper()
	header, err := json.Marshal(map[string]string{"alg": "RS256", "kid": keyID, "typ": "JWT"})
	if err != nil {
		t.Fatal(err)
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatal(err)
	}
	encodedHeader := base64.RawURLEncoding.EncodeToString(header)
	encodedPayload := base64.RawURLEncoding.EncodeToString(payload)
	hasher := crypto.SHA256.New()
	_, _ = hasher.Write([]byte(encodedHeader + "." + encodedPayload))
	signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, hasher.Sum(nil))
	if err != nil {
		t.Fatal(err)
	}
	return encodedHeader + "." + encodedPayload + "." + base64.RawURLEncoding.EncodeToString(signature)
}
