package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, Long> {
    @Query("""
            select profile
            from UserProfile profile
            join fetch profile.user user
            where user = :user
            """)
    Optional<UserProfile> findByUser(User user);

    @Query("""
            select profile
            from UserProfile profile
            join fetch profile.user user
            where user.id = :userId
            """)
    Optional<UserProfile> findByUserId(Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select profile
            from UserProfile profile
            join fetch profile.user user
            where user.id = :userId
            """)
    Optional<UserProfile> findByUserIdForUpdate(@Param("userId") Long userId);

    @Query("""
            select profile
            from UserProfile profile
            join profile.user user
            where lower(profile.nickname) like lower(concat('%', :keyword, '%'))
               or lower(user.email) like lower(concat('%', :keyword, '%'))
            """)
    List<UserProfile> searchUsers(@Param("keyword") String keyword);
}
