// Test script for verifying system prompt behavior and conditional question_type.
const path = require("path");
const fs = require("fs");
const dotenv = require("dotenv");

// Load .env
const envCandidates = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, ".env")
];
for (const cand of envCandidates) {
  if (fs.existsSync(cand)) {
    dotenv.config({ path: cand });
    break;
  }
}

const { runOpenAIFlow } = require("./companion-agent-services");

async function runTests() {
  const testCases = [
    {
      name: "1. Single Dish Advice (single_dish)",
      prompt: "我今天晚餐想吃一碗紅燒牛肉麵，請問這樣會不會太油或熱量太高？"
    },
    {
      name: "2. Dish Comparison (dish_comparison)",
      prompt: "去滷味攤不知道要點乾意麵還是切汁米血跟豆干，這兩個哪一個熱量比較低？"
    },
    {
      name: "3. Cross Meal Advice (dish_comparison)",
      prompt: "我中午吃了麥當勞的大麥克套餐，那晚餐吃鹽水雞搭配蔬菜是不是比較合適？"
    },
    {
      name: "4. Meal Record - Single Meal",
      prompt: "幫我記錄一下，我今天早上吃了一顆茶葉蛋和一杯無糖高纖豆漿。"
    },
    {
      name: "5. Meal Record - Cross Meal Periods",
      prompt: "幫我記一下飲食，我上午吃了一份鮪魚蛋吐司，中午吃了一盒舒肥雞胸肉沙拉。"
    },
    {
      name: "6. General Chat / Off-topic (should_handle: false)",
      prompt: "今天台北天氣好冷喔，你覺得我下午應該去哪裡散步比較好？"
    }
  ];

  console.log("Starting LLM Prompt & Schema verification...\n");

  for (const tc of testCases) {
    console.log(`[Test Case] ${tc.name}`);
    console.log(`Input: "${tc.prompt}"`);
    try {
      const result = await runOpenAIFlow(tc.prompt);
      console.log("Result Screening:", JSON.stringify(result.screening, null, 2));
      console.log("Result Emotion:", JSON.stringify(result.emotion, null, 2));
      console.log("Dietary Agent Request Payload:", JSON.stringify(result.dietary_agent_request, null, 2));
      console.log("-------------------------------------------\n");
    } catch (err) {
      console.error("Test Case Failed with error:", err.message);
      console.log("-------------------------------------------\n");
    }
  }
}

runTests();
