// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-helpers.js
// Description: Rule-based checks, pre-checks, fallback evaluations, and sanitize logic

/**
 * 1. Pre-check 安全防護：醫療診斷詞過濾
 * 利用正則表達式偵測是否含有特定診斷或醫囑用詞。
 * 這用來當作 Pre-check 與 Post-check 的核心，防止模型涉入醫療診斷。
 */
function isMedicalOutOfScope(message) {
  return (
    /(診斷|處方|藥|醫生|治療|病名確診|服用方法)/.test(message) ||
    /(diagnosis|prescription|treatment|medicine|doctor)/i.test(message)
  );
}

/**
 * 2. 飲食相關詞預檢
 * 用於粗略判斷使用者問題是否跟常見食物或熱量有關係。
 */
function isLikelyFoodRelated(message) {
  return (
    /(吃|餐廳|料理|菜單|便當|晚餐|午餐|早餐|熱量|營養|外食|拉麵|火鍋|炸雞|沙拉|飲料|宵夜|牛肉麵|雞排|減脂|增肌|飲食)/.test(message) ||
    /(food|menu|restaurant|dish|meal|calorie|nutrition)/i.test(message)
  );
}


/**
 * 3. 比較語意預檢
 * 用來快速辨識使用者問題中是否包含了比較詞彙（例如 A 還是 B 哪個好）。
 */
function looksLikeComparison(message) {
  return /(哪個|比較|vs|versus|跟|和|相比|比較適合)/i.test(message);
}

// TODO:這部分的邏輯還需要討論，原本沒有md沒有這一函式，但確實如果因為openai無法連線，我們仍需要有資料手動進行資料傳遞，但是透過一個個比較串列的方式有點太過陽春。
/**
 * 4. 本地料理名稱備援抽取 (Fallback Extraction)
 * 當 OpenAI 連線不可用時，利用一組預定義的常見食物關鍵字在 message 中比對並抽取。
 * 這是為了防止系統崩潰時，無法回傳 "dishes" 陣列給後端。
 */
function fallbackDishesExtraction(message) {
  const commonFoods = ["拉麵", "炸雞", "火鍋", "沙拉", "便當", "牛肉麵", "雞排", "宵夜", "飲料", "咖哩飯", "披薩", "壽司"];
  const found = [];
  commonFoods.forEach(food => {
    if (message.includes(food)) {
      found.push(food); // 逐一匹配，並推進陣列中
    }
  });
  return found;
}

/**
 * 5. 保底問題分類器
 * 依據 Pre-check 的規則對問題種類 (question_type) 進行最基本的歸類。
 */
function fallbackClassifyQuestionType(message) {
  if (looksLikeComparison(message)) return "dish_comparison";
  if (isLikelyFoodRelated(message)) return "single_dish";
  return "unknown";
}

/**
 * 6. 保底意圖過濾器 (Fallback Screening)
 * 當 OpenAI Responses API 失效時執行。
 * 它依然會確保：醫療詞攔截、無個人 profile 時阻擋並轉為「需要補充資訊」。
 */
function fallbackScreening(message, userContext) {
  const isFood = isLikelyFoodRelated(message);
  const isMedical = isMedicalOutOfScope(message);

  // 若包含醫療詞，強制不接手 (should_handle = false)
  if (isMedical) {
    return {
      should_handle: false,
      intent_category: "medical_out_of_scope",
      question_type: "unknown",
      requires_more_context: false,
      missing_information: [],
      confidence: 0.8,
      dishes: []
    };
  }

  // 飲食問題保底：若缺乏 Profile，標記 requires_more_context = true 並記錄 missing user_profile
  return {
    should_handle: isFood,
    intent_category: isFood ? "dish_advice" : "general_chat",
    question_type: fallbackClassifyQuestionType(message),
    requires_more_context: isFood && !userContext.has_user_profile,
    missing_information: (isFood && !userContext.has_user_profile) ? ["user_profile"] : [],
    confidence: 0.6,
    dishes: fallbackDishesExtraction(message)
  };
}

/**
 * 7. 保底情緒分析器 (Fallback Emotion)
 * 當 OpenAI Responses API 失效時，利用本地正則關鍵字分析焦慮、罪惡、壓力等。
 * 用於維持最低限度的回覆同理心安撫功能。
 */
function fallbackEmotion(message) {
  const containsAnxiety = /(焦慮|擔心|害怕|緊張|怎麼辦|會不會太|超標)/.test(message);
  const containsGuilt = /(罪惡感|內疚|後悔|偷吃)/.test(message);
  const containsStress = /(壓力|累|崩潰|煩)/.test(message);

  let primary_emotion = "neutral";
  let needs_empathy = false;
  let companion_tone = "neutral";

  // 情緒規則匹配：設定安撫標籤與陪伴語氣
  if (containsAnxiety) {
    primary_emotion = "anxiety";
    needs_empathy = true;
    companion_tone = "calm";
  } else if (containsGuilt) {
    primary_emotion = "guilt";
    needs_empathy = true;
    companion_tone = "encouraging";
  } else if (containsStress) {
    primary_emotion = "stress";
    needs_empathy = true;
    companion_tone = "calm";
  }

  return {
    primary_emotion,
    valence: needs_empathy ? "negative" : "neutral",
    urgency: "medium",
    needs_empathy,
    companion_tone,
    evidence: []
  };
}

/**
 * 8. Post-check 意圖修正 (Sanitize Screening)
 * 【極重要】當 OpenAI 回傳結果後，以此函式進行二次檢驗，覆寫模型的不合理輸出。
 * 這是決定系統安全與資料一致性的防護線。
 */
function sanitizeScreening(raw, message, userContext) {
  // 如果 LLM 沒有回傳任何 arguments 物件，直接走保底流程
  if (!raw) {
    return fallbackScreening(message, userContext);
  }

  // 淺拷貝 LLM 回傳的結果
  const result = { ...raw };

  // 強制規則一：若本地 Pre-check 抓到敏感醫療詞彙，強制覆寫為 Out of Scope，以策安全
  if (isMedicalOutOfScope(message)) {
    result.should_handle = false;
    result.intent_category = "medical_out_of_scope";
    result.question_type = "unknown";
  }

  // 確保 missing_information 必定是陣列結構
  if (!Array.isArray(result.missing_information)) {
    result.missing_information = Array.isArray(raw.missing_information) ? raw.missing_information : [];
  }

  // 強制規則二：若系統沒有載入 user profile，但模型將 requires_more_context 誤判為 false，強制將其覆寫為 true
  if (result.should_handle && !userContext.has_user_profile && !result.requires_more_context) {
    result.requires_more_context = true;
    if (!result.missing_information.includes("user_profile")) {
      result.missing_information.push("user_profile");
    }
  }

  // 確保 dishes 必定是陣列結構，若模型漏填，以本地 regex 抽取保底
  if (!Array.isArray(result.dishes)) {
    result.dishes = Array.isArray(raw.dishes) ? raw.dishes : fallbackDishesExtraction(message);
  }

  return result;
}

/**
 * 9. Post-check 情緒修正 (Sanitize Emotion)
 * 驗證 OpenAI 回傳的情緒結構。若無回傳或屬性缺漏，用保底資訊補齊。
 */
function sanitizeEmotion(raw, message) {
  if (!raw) {
    return fallbackEmotion(message);
  }
  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    // 確保 needs_empathy 是正確的 boolean 型態，不為 undefined
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

/**
 * 10. 封裝傳遞給 Dietary Agent 的三元素 Payload
 * 【本階段核心變更】如果分析判定可以處理 (should_handle = true) 且資料足夠，
 * 則組裝僅含 `question`、`question_type`、`dishes` 的三元素 JSON 物件傳遞給組員的 Dietary Agent。
 * 否則回傳 null。
 */
function buildDietaryAgentRequest(screening, message) {
  if (!screening.should_handle || screening.requires_more_context) {
    return null;
  }

  //TODO:按照規定回傳三個屬性，查看後端DTO:DietaryAgentPayload ，命名為:question、question_type、dish_names (Json的資料結構是key-value，所以其名稱必須完全一樣)
  return {
    question: message,
    question_type: screening.question_type,
    dish_names: screening.dishes || []
  };
}

// 匯出所有的規則與輔助函式，供 services.js 呼叫
module.exports = {
  isMedicalOutOfScope,
  isLikelyFoodRelated,
  looksLikeComparison,
  fallbackDishesExtraction,
  fallbackClassifyQuestionType,
  fallbackScreening,
  fallbackEmotion,
  sanitizeScreening,
  sanitizeEmotion,
  buildDietaryAgentRequest
};
