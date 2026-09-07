UPDATE user_profile
SET gender = CASE
    WHEN UPPER(LTRIM(RTRIM(gender))) IN ('FEMALE', 'F', N'女', N'女性') THEN 'FEMALE'
    WHEN UPPER(LTRIM(RTRIM(gender))) IN ('MALE', 'M', N'男', N'男性') THEN 'MALE'
    ELSE UPPER(LTRIM(RTRIM(gender)))
END;

UPDATE user_profile
SET diet_goal = CASE
    WHEN UPPER(LTRIM(RTRIM(diet_goal))) IN ('LOSE_WEIGHT', 'LOSE_FAT', N'減脂', N'減重') THEN 'LOSE_WEIGHT'
    WHEN UPPER(LTRIM(RTRIM(diet_goal))) IN ('GAIN_MUSCLE', N'增肌') THEN 'GAIN_MUSCLE'
    WHEN UPPER(LTRIM(RTRIM(diet_goal))) IN ('MAINTAIN', N'養生', N'維持', N'健康飲食') THEN 'MAINTAIN'
    ELSE UPPER(LTRIM(RTRIM(diet_goal)))
END;

UPDATE user_profile
SET pet_type = CASE
    WHEN UPPER(LTRIM(RTRIM(pet_type))) IN ('DOG', N'狗', N'奶油皮丘', N'米粒(MILI)') THEN 'DOG'
    WHEN UPPER(LTRIM(RTRIM(pet_type))) IN ('CAT', N'貓', N'貓兒') THEN 'CAT'
    ELSE UPPER(LTRIM(RTRIM(pet_type)))
END;

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'無特殊疾病', 'NONE');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'無疾病', 'NONE');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'高血壓', 'HYPERTENSION');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'高血脂', 'HYPERLIPIDEMIA');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'糖尿病', 'DIABETES');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'心血管疾病', 'CARDIOVASCULAR');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'慢性腎臟病', 'KIDNEY_DISEASE');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'腎臟病', 'KIDNEY_DISEASE');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'腦中風', 'STROKE');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'代謝症候群', 'METABOLIC_SYNDROME');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'高尿酸血症', 'HYPERURICEMIA');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'胃食道逆流', 'GERD');

UPDATE user_profile
SET health_conditions = REPLACE(health_conditions, N'痛風', 'GOUT');

UPDATE user_profile
SET health_conditions = UPPER(LTRIM(RTRIM(health_conditions)));
