package com.tku.dietary_app.service;

import io.jsonwebtoken.*;//匯入 JWT 套件的核心類別，建立 token、解析 token、驗證 token
import io.jsonwebtoken.security.Keys;//用來建立加密用的 key
import org.springframework.stereotype.Component;

import java.security.Key;//代表加密用的金鑰
import java.util.Date;//匯入 Date 類別。用來設定：token 建立時間，token 過期時間

// JWT 工具類別，提供生成和驗證 JWT Token 的功能
@Component
public class JwtUtil {
    //設定 JWT 的「密鑰」，這是一段用來加密 token 的字串(簽名)
    private final String SECRET = "DietaryAppSecretKeyForJWTAuthentication123456";

    //把剛剛的 SECRET 字串轉成加密用的 Key 物件，使用HMAC SHA-256加密
    private final Key key = Keys.hmacShaKeyFor(SECRET.getBytes());

    //設定 token 的有效時間
    private final long EXPIRATION = 1000 * 60 * 60; // 1 hour

    // 生成 JWT Token
    public String generateToken(String email) {
        return Jwts.builder()
                .setSubject(email)//之後解析 token 時，就可以取得 email
                .setIssuedAt(new Date())//設定 token 的建立時間
                .setExpiration(new Date(System.currentTimeMillis() + EXPIRATION))//設定 token 的過期時間
                .signWith(key, SignatureAlgorithm.HS256)//用 key 進行簽名，產生Signature
                .compact();//把前面設定的資料組合成一個 JWT 字串
    }

    // 驗證 JWT Token 並返回主題
    public String validateToken(String token) {
        return Jwts.parserBuilder()//用來解析 token
                .setSigningKey(key)
                .build()//建立 parser 物件，= 解析器 ，就是一個「負責把 token 拆開、檢查、讀取內容」的工具
                .parseClaimsJws(token)//解析 token
                .getBody()//取得 token 裡面的資料
                .getSubject();//取得 subject(email)
    }
}