package com.tku.dietary_app.service;

import com.tku.dietary_app.exception.FileValidationException;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class ImageStorageService {
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
            "image/jpeg",
            "image/png",
            "image/webp"
    );
    private static final Map<String, String> EXTENSION_BY_TYPE = Map.of(
            "image/jpeg", ".jpg",
            "image/png", ".png",
            "image/webp", ".webp"
    );

    public String storeImage(MultipartFile file, Path directory, String filenamePrefix) throws IOException {
        String contentType = normalizeContentType(file.getContentType());
        if (!ALLOWED_CONTENT_TYPES.contains(contentType)) {
            throw new FileValidationException("僅支援 JPEG、PNG、WEBP 圖片");
        }

        String detectedType = detectContentType(file);
        if (!contentType.equals(detectedType)) {
            throw new FileValidationException("檔案內容與副檔名或 Content-Type 不一致");
        }

        String extension = resolveExtension(file.getOriginalFilename(), contentType);
        String filename = filenamePrefix + "_" + UUID.randomUUID() + extension;

        Files.createDirectories(directory);
        try (InputStream inputStream = file.getInputStream()) {
            Files.copy(inputStream, directory.resolve(filename), StandardCopyOption.REPLACE_EXISTING);
        }

        return filename;
    }

    private String normalizeContentType(String contentType) {
        return contentType == null ? "" : contentType.trim().toLowerCase(Locale.ROOT);
    }

    private String resolveExtension(String originalFilename, String contentType) {
        String expectedExtension = EXTENSION_BY_TYPE.get(contentType);
        String originalExtension = extractExtension(originalFilename);
        if (originalExtension.isEmpty()) {
            return expectedExtension;
        }

        if (contentType.equals("image/jpeg") && (originalExtension.equals(".jpg") || originalExtension.equals(".jpeg"))) {
            return ".jpg";
        }

        if (!originalExtension.equals(expectedExtension)) {
            throw new FileValidationException("副檔名與圖片格式不一致");
        }

        return expectedExtension;
    }

    private String extractExtension(String filename) {
        if (filename == null) {
            return "";
        }

        int extensionIndex = filename.lastIndexOf('.');
        if (extensionIndex < 0) {
            return "";
        }

        return filename.substring(extensionIndex).toLowerCase(Locale.ROOT);
    }

    private String detectContentType(MultipartFile file) throws IOException {
        byte[] header;
        try (InputStream inputStream = file.getInputStream()) {
            header = inputStream.readNBytes(12);
        }

        if (header.length >= 3
                && (header[0] & 0xFF) == 0xFF
                && (header[1] & 0xFF) == 0xD8
                && (header[2] & 0xFF) == 0xFF) {
            return "image/jpeg";
        }

        if (header.length >= 8
                && (header[0] & 0xFF) == 0x89
                && header[1] == 0x50
                && header[2] == 0x4E
                && header[3] == 0x47
                && header[4] == 0x0D
                && header[5] == 0x0A
                && header[6] == 0x1A
                && header[7] == 0x0A) {
            return "image/png";
        }

        if (header.length >= 12
                && header[0] == 0x52
                && header[1] == 0x49
                && header[2] == 0x46
                && header[3] == 0x46
                && header[8] == 0x57
                && header[9] == 0x45
                && header[10] == 0x42
                && header[11] == 0x50) {
            return "image/webp";
        }

        throw new FileValidationException("無法辨識圖片格式，請上傳有效的 JPEG、PNG、WEBP");
    }
}
