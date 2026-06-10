// C FFI declarations for skills-core Rust library
// Will be populated with asm_* function prototypes

#include <stdint.h>

// Memory management
void* asm_init(const char* source_root);
void  asm_destroy(void* handle);
void  asm_free_string(char* ptr);
char* asm_expand_path(const char* path);

// Agent management
char* asm_list_agents(void* handle);
char* asm_add_custom_agent(void* handle, const char* json);
uint8_t asm_remove_custom_agent(void* handle, const char* agent_id);

// Skill management
char* asm_list_skills(void* handle);
char* asm_get_skill(void* handle, const char* skill_id);
uint8_t asm_delete_skill(void* handle, const char* skill_id);
char* asm_detect_new_skills(void* handle);
char* asm_fetch_agent_skills(void* handle);

// Symlink operations
uint8_t asm_create_symlink(void* handle, const char* agent_id, const char* skill_id);
uint8_t asm_remove_symlink(void* handle, const char* agent_id, const char* skill_id);

// Git sync
char* asm_get_git_status(void* handle);
char* asm_stage_and_push(void* handle);
char* asm_get_pending_changes(void* handle);

// File watcher
uint8_t asm_start_watcher(void* handle);
void  asm_stop_watcher(void* handle);

// Skill organization
uint8_t asm_organize_skill(void* handle, const char* skill_id, const char* agent_id);
char* asm_organize_all(void* handle);
char* asm_get_skill_list(void* handle);
uint8_t asm_has_organized(void* handle);
void  asm_set_organized(void* handle);
uint8_t asm_refresh_skill_db(void* handle);
uint8_t asm_restore_skill(void* handle, const char* skill_id);
