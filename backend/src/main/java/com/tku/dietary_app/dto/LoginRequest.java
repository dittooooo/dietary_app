package com.tku.dietary_app.dto;
//定義登入 API 要接收的資料格式，並驗證輸入是否符合規則

import jakarta.validation.constraints.NotBlank;//欄位不能是 null，也不能是空字串，也不能只輸入空白
import jakarta.validation.constraints.Pattern;//用正規表達式（regex）檢查字串格式
import jakarta.validation.constraints.Size;//限制字串長度
import lombok.Data;//自動有getter/setter

// 登入請求資料傳輸物件，包含登入所需的欄位
@Data
public class LoginRequest {

    @NotBlank(message = "請輸入電子郵件")
    @Pattern(regexp = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$",message = "電子郵件格式不正確")
    private String email;

    @NotBlank(message = "請輸入密碼")
    @Size(min = 6, max = 18, message = "長度需為 6-18 位")
    @Pattern(regexp = ".*[a-z].*", message = "密碼必須包含小寫英文字母")
    @Pattern(regexp = ".*[A-Z].*", message = "密碼必須包含大寫英文字母")
    @Pattern(regexp = ".*[0-9].*", message = "密碼必須包含至少一個數字")
    private String password;
}
