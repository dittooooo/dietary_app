// Path: companion_js/prompts/index.js
// Description: Central export point for all Companion Agent system prompts and tools schemas

const { ANALYSIS_SYSTEM_PROMPT, tools } = require("./analysisPrompt");
const { REPLY_SYSTEM_PROMPT } = require("./replyPrompt");
const { TRANSLATION_SYSTEM_PROMPT } = require("./translationPrompt");

module.exports = {
  ANALYSIS_SYSTEM_PROMPT,
  tools,
  REPLY_SYSTEM_PROMPT,
  TRANSLATION_SYSTEM_PROMPT
};
