package com.tku.dietary_app.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.util.Date;

@Component
public class JwtUtil {
    private static final String TOKEN_TYPE_CLAIM = "token_type";
    private static final String ACCESS_TOKEN_TYPE = "access";
    private static final String REFRESH_TOKEN_TYPE = "refresh";

    private final Key key;
    private final long accessTokenExpirationSeconds;
    private final long refreshTokenExpirationSeconds;

    public JwtUtil(@Value("${jwt.secret}") String secret,
                   @Value("${jwt.access-token-expiration-seconds:1800}") long accessTokenExpirationSeconds,
                   @Value("${jwt.refresh-token-expiration-seconds:2592000}") long refreshTokenExpirationSeconds) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessTokenExpirationSeconds = accessTokenExpirationSeconds;
        this.refreshTokenExpirationSeconds = refreshTokenExpirationSeconds;
    }

    public String generateAccessToken(String email) {
        return generateToken(email, ACCESS_TOKEN_TYPE, accessTokenExpirationSeconds);
    }

    public String generateRefreshToken(String email) {
        return generateToken(email, REFRESH_TOKEN_TYPE, refreshTokenExpirationSeconds);
    }

    public String validateAccessToken(String token) {
        return validateTokenByType(token, ACCESS_TOKEN_TYPE);
    }

    public String validateRefreshToken(String token) {
        return validateTokenByType(token, REFRESH_TOKEN_TYPE);
    }

    public long getAccessTokenExpirationSeconds() {
        return accessTokenExpirationSeconds;
    }

    public long getRefreshTokenExpirationSeconds() {
        return refreshTokenExpirationSeconds;
    }

    private String generateToken(String email, String tokenType, long expirationSeconds) {
        long now = System.currentTimeMillis();
        return Jwts.builder()
                .setSubject(email)
                .claim(TOKEN_TYPE_CLAIM, tokenType)
                .setIssuedAt(new Date(now))
                .setExpiration(new Date(now + expirationSeconds * 1000))
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();
    }

    private String validateTokenByType(String token, String expectedTokenType) {
        Claims claims = Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
                .getBody();

        String tokenType = claims.get(TOKEN_TYPE_CLAIM, String.class);
        if (!expectedTokenType.equals(tokenType)) {
            throw new IllegalArgumentException("token type 不符");
        }

        return claims.getSubject();
    }
}
