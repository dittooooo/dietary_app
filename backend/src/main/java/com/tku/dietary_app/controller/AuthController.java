//它會接收前端送來的 JSON 資料，交給 AuthService 處理，然後把結果回傳給前端
package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.LoginRequest;//用來接收前端送來的登入資料
import com.tku.dietary_app.dto.RegisterRequest;//用來接收前端送來的註冊資料
import com.tku.dietary_app.service.AuthService;//Controller 不自己做註冊/登入邏輯，而是交給 AuthService 去處理
import jakarta.validation.Valid;//匯入 @Valid，這個註解用來做輸入資料驗證
import lombok.RequiredArgsConstructor;//自動產生建構子
import org.springframework.web.bind.annotation.*;//匯入 Spring Web 裡跟 API 註解有關的東西
import org.springframework.http.ResponseEntity;//匯入 ResponseEntity。它可以讓你自訂 HTTP 回應內容

//匯入 Java 的 HashMap 和 Map。
//這裡是用來組裝回傳給前端的 JSON 資料
import java.util.HashMap;
import java.util.Map;

/**
 * 認證相關控制器 (Authentication Controller)
 * 負責處理使用者的註冊與登入流程
 */
@RestController//表示這個類別是一個 REST API 控制器，作用：讓 Spring 知道這是一個 Controller方法回傳的內容會直接變成 HTTP Response Body
@RequestMapping("/api")//設定這個 Controller 的共同路徑前綴
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    /**
     * [POST] 使用者註冊
     * * @param request 包含 email, password 的 JSON 物件
     * @return 註冊成功訊息 (String)
     * * 前端注意：
     * 1. 需符合 RegisterRequest 中的欄位驗證 (如 Email 格式)。
     * 2. 成功時回傳 "Register Success"。
     * 3. 失敗時會根據異常回傳錯誤訊息。
     */
    @PostMapping("/register")
    public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest request) {
        try {
            String registerResult = authService.register(request);

            // 註冊成功後自動登入
            LoginRequest loginRequest = new LoginRequest();
            loginRequest.setEmail(request.getEmail());
            loginRequest.setPassword(request.getPassword());

            String token = authService.login(loginRequest);

            //建立一個 Map，準備組裝回傳給前端的 JSON
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "註冊成功，請完成 onboarding");
            response.put("token", token);
            response.put("needsOnboarding", true);

            return ResponseEntity.ok(response);//回傳 HTTP 200 OK，並把 response 當成 JSON 回給前端

        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("success", false);
            error.put("message", "註冊失敗：" + e.getMessage());
            return ResponseEntity.status(400).body(error);//回傳 HTTP 狀態碼 400 Bad Request，並把 error JSON 回給前端
        }
    }
    /**
     * [POST] 使用者登入
     * * @param request 包含 email, password 的 JSON 物件
     * @return 成功登入後核發的 JWT Token (String)
     * * 前端注意：
     * 1. 登入成功後請將回傳的 Token 儲存於 localStorage 或 Cookie。
     * 2. 後續需要權限的請求，需在 Header 帶上：Authorization: Bearer <Token>。
     */
    @PostMapping("/login")
    //直接呼叫 authService.login(request)，並把結果回傳出去
    public String login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request);
    }


}
