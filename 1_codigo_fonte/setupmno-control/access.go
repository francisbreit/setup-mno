package main

import (
	"context"
	"crypto"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	accessHeader       = "Cf-Access-Jwt-Assertion"
	accessJWKSMaxBytes = 1 << 20
	accessKeyCacheTTL  = 6 * time.Hour
	accessClockSkew    = time.Minute
)

type accessIdentity struct {
	Subject string
	Email   string
	Expires time.Time
}

type accessVerifier struct {
	required     bool
	issuer       string
	audience     string
	allowedEmail string
	certsURL     string
	client       *http.Client
	now          func() time.Time

	mu        sync.Mutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

type accessJWTHeader struct {
	Algorithm string `json:"alg"`
	KeyID     string `json:"kid"`
	Type      string `json:"typ"`
}

type accessJWTClaims struct {
	Issuer    string          `json:"iss"`
	Audience  json.RawMessage `json:"aud"`
	Subject   string          `json:"sub"`
	Email     string          `json:"email"`
	ExpiresAt json.Number     `json:"exp"`
	NotBefore json.Number     `json:"nbf"`
	IssuedAt  json.Number     `json:"iat"`
}

type accessJWKSet struct {
	Keys []struct {
		KeyID     string `json:"kid"`
		KeyType   string `json:"kty"`
		Algorithm string `json:"alg"`
		Use       string `json:"use"`
		Modulus   string `json:"n"`
		Exponent  string `json:"e"`
	} `json:"keys"`
}

func newAccessVerifier(required bool, teamDomain, audience, allowedEmail string, client *http.Client) (*accessVerifier, error) {
	if !required {
		return &accessVerifier{required: false}, nil
	}
	issuer, err := normalizeAccessTeamDomain(teamDomain)
	if err != nil {
		return nil, err
	}
	audience = strings.TrimSpace(audience)
	if len(audience) < 16 || len(audience) > 128 || strings.ContainsAny(audience, " \t\r\n") {
		return nil, errors.New("audiência do Cloudflare Access inválida")
	}
	allowedEmail = strings.ToLower(strings.TrimSpace(allowedEmail))
	if !validAccessEmail(allowedEmail) {
		return nil, errors.New("e-mail autorizado do Cloudflare Access inválido")
	}
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	return &accessVerifier{
		required:     true,
		issuer:       issuer,
		audience:     audience,
		allowedEmail: allowedEmail,
		certsURL:     issuer + "/cdn-cgi/access/certs",
		client:       client,
		now:          time.Now,
		keys:         make(map[string]*rsa.PublicKey),
	}, nil
}

func normalizeAccessTeamDomain(value string) (string, error) {
	value = strings.TrimRight(strings.TrimSpace(value), "/")
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil ||
		parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return "", errors.New("domínio da equipe Cloudflare Access inválido")
	}
	host := strings.ToLower(parsed.Hostname())
	if !strings.HasSuffix(host, ".cloudflareaccess.com") || parsed.Port() != "" {
		return "", errors.New("domínio da equipe Cloudflare Access não é oficial")
	}
	return "https://" + host, nil
}

func validAccessEmail(value string) bool {
	if len(value) < 5 || len(value) > 254 || strings.ContainsAny(value, " <>\t\r\n") {
		return false
	}
	parts := strings.Split(value, "@")
	return len(parts) == 2 && parts[0] != "" && strings.Contains(parts[1], ".") &&
		!strings.HasPrefix(parts[1], ".") && !strings.HasSuffix(parts[1], ".")
}

func (v *accessVerifier) middleware(next http.Handler) http.Handler {
	if v == nil || !v.required {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// O healthcheck é alcançável somente pela rede overlay interna e não
		// representa uma sessão de usuário. Todo o restante exige Access.
		if r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		identity, err := v.verify(r.Context(), r.Header.Get(accessHeader))
		if err != nil {
			writeError(w, http.StatusUnauthorized, "identidade Cloudflare Access inválida")
			return
		}
		ctx := context.WithValue(r.Context(), accessIdentityContextKey{}, identity)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (v *accessVerifier) verify(ctx context.Context, token string) (*accessIdentity, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(token) > 16<<10 {
		return nil, errors.New("token Access ausente ou malformado")
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, errors.New("cabeçalho JWT inválido")
	}
	var header accessJWTHeader
	if err := json.Unmarshal(headerBytes, &header); err != nil || header.Algorithm != "RS256" ||
		header.KeyID == "" || len(header.KeyID) > 256 {
		return nil, errors.New("algoritmo ou chave JWT inválidos")
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, errors.New("payload JWT inválido")
	}
	var claims accessJWTClaims
	decoder := json.NewDecoder(strings.NewReader(string(payloadBytes)))
	decoder.UseNumber()
	if err := decoder.Decode(&claims); err != nil {
		return nil, errors.New("claims JWT inválidos")
	}
	if claims.Issuer != v.issuer || !audienceContains(claims.Audience, v.audience) {
		return nil, errors.New("emissor ou audiência JWT inválidos")
	}
	now := v.now()
	expires, err := jwtNumericTime(claims.ExpiresAt)
	if err != nil || !now.Before(expires.Add(accessClockSkew)) {
		return nil, errors.New("token Access expirado")
	}
	if claims.NotBefore != "" {
		notBefore, err := jwtNumericTime(claims.NotBefore)
		if err != nil || now.Add(accessClockSkew).Before(notBefore) {
			return nil, errors.New("token Access ainda não é válido")
		}
	}
	if claims.IssuedAt != "" {
		issuedAt, err := jwtNumericTime(claims.IssuedAt)
		if err != nil || issuedAt.After(now.Add(accessClockSkew)) {
			return nil, errors.New("emissão do token Access inválida")
		}
	}
	email := strings.ToLower(strings.TrimSpace(claims.Email))
	if claims.Subject == "" || email != v.allowedEmail {
		return nil, errors.New("identidade Access não autorizada")
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, errors.New("assinatura JWT inválida")
	}
	digest := crypto.SHA256.New()
	_, _ = digest.Write([]byte(parts[0] + "." + parts[1]))
	hash := digest.Sum(nil)
	key, err := v.keyFor(ctx, header.KeyID, false)
	if err != nil {
		return nil, err
	}
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, hash, signature); err != nil {
		key, refreshErr := v.keyFor(ctx, header.KeyID, true)
		if refreshErr != nil || rsa.VerifyPKCS1v15(key, crypto.SHA256, hash, signature) != nil {
			return nil, errors.New("assinatura JWT recusada")
		}
	}
	return &accessIdentity{Subject: claims.Subject, Email: email, Expires: expires}, nil
}

func (v *accessVerifier) keyFor(ctx context.Context, keyID string, force bool) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	now := v.now()
	if !force && now.Sub(v.fetchedAt) < accessKeyCacheTTL {
		if key := v.keys[keyID]; key != nil {
			return key, nil
		}
	}
	if err := v.refreshKeys(ctx); err != nil {
		return nil, err
	}
	key := v.keys[keyID]
	if key == nil {
		return nil, errors.New("chave de assinatura Access desconhecida")
	}
	return key, nil
}

func (v *accessVerifier) refreshKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.certsURL, nil)
	if err != nil {
		return errors.New("não foi possível preparar a consulta de chaves Access")
	}
	req.Header.Set("Accept", "application/json")
	resp, err := v.client.Do(req)
	if err != nil {
		return errors.New("chaves públicas do Cloudflare Access indisponíveis")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("consulta de chaves Access retornou HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, accessJWKSMaxBytes+1))
	if err != nil || len(data) == 0 || len(data) > accessJWKSMaxBytes {
		return errors.New("conjunto de chaves Access inválido")
	}
	var set accessJWKSet
	if err := json.Unmarshal(data, &set); err != nil || len(set.Keys) == 0 || len(set.Keys) > 8 {
		return errors.New("conjunto de chaves Access malformado")
	}
	keys := make(map[string]*rsa.PublicKey, len(set.Keys))
	for _, item := range set.Keys {
		if item.KeyID == "" || item.KeyType != "RSA" || item.Algorithm != "RS256" || item.Use != "sig" {
			continue
		}
		modulus, err := base64.RawURLEncoding.DecodeString(item.Modulus)
		if err != nil || len(modulus) < 256 || len(modulus) > 1024 {
			continue
		}
		exponentBytes, err := base64.RawURLEncoding.DecodeString(item.Exponent)
		if err != nil || len(exponentBytes) == 0 || len(exponentBytes) > 4 {
			continue
		}
		exponent := 0
		for _, value := range exponentBytes {
			exponent = exponent<<8 | int(value)
		}
		if exponent < 3 || exponent%2 == 0 {
			continue
		}
		keys[item.KeyID] = &rsa.PublicKey{N: new(big.Int).SetBytes(modulus), E: exponent}
	}
	if len(keys) == 0 {
		return errors.New("nenhuma chave RSA confiável foi publicada pelo Access")
	}
	v.keys = keys
	v.fetchedAt = v.now()
	return nil
}

func audienceContains(raw json.RawMessage, expected string) bool {
	var single string
	if json.Unmarshal(raw, &single) == nil {
		return single == expected
	}
	var multiple []string
	if json.Unmarshal(raw, &multiple) != nil || len(multiple) == 0 || len(multiple) > 16 {
		return false
	}
	for _, value := range multiple {
		if value == expected {
			return true
		}
	}
	return false
}

func jwtNumericTime(value json.Number) (time.Time, error) {
	seconds, err := value.Int64()
	if err != nil || seconds <= 0 {
		return time.Time{}, errors.New("timestamp JWT inválido")
	}
	return time.Unix(seconds, 0), nil
}

type accessIdentityContextKey struct{}

func accessIdentityFromContext(ctx context.Context) *accessIdentity {
	identity, _ := ctx.Value(accessIdentityContextKey{}).(*accessIdentity)
	return identity
}
