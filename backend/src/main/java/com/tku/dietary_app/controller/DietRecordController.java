package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.DietRecordService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

@RestController
@RequestMapping("/api/diet-records")
@RequiredArgsConstructor
public class DietRecordController {

    private final DietRecordService dietRecordService;
    private final UserRepository userRepository;

    private User getLoginUser() {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
        return userRepository.findByEmail(email).orElseThrow(() -> new RuntimeException("使用者不存在"));
    }

    @GetMapping
    public ResponseEntity<?> getRecords() {
        User user = getLoginUser();
        return ResponseEntity.ok(dietRecordService.getRecordsByUser(user.getId()));
    }

    @PostMapping
    public ResponseEntity<?> create(@RequestBody DietRecordRequest request) {
        User user = getLoginUser();
        return ResponseEntity.ok(dietRecordService.create(user.getId(), request));
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> update(@PathVariable Long id, @RequestBody DietRecordRequest request) {
        User user = getLoginUser();
        return ResponseEntity.ok(dietRecordService.update(id, user.getId(), request));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> delete(@PathVariable Long id) {
        User user = getLoginUser();
        dietRecordService.delete(id, user.getId());
        return ResponseEntity.ok("刪除成功");
    }

    @PostMapping("/{id}/photo")
    public ResponseEntity<?> uploadPhoto(@PathVariable Long id, @RequestParam("file") MultipartFile file) throws IOException {
        User user = getLoginUser();
        return ResponseEntity.ok(dietRecordService.savePhoto(id, user.getId(), file));
    }
}
