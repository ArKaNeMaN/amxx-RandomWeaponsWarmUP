#if defined __rww_included
    #endinput
#endif
#define __rww_included

/**
 * Вызывается в начале разминки
 *
 * @noreturn
 */
forward RWW_OnStarted();

/**
 * Вызывается в конце разминки
 *
 * @noreturn
 */
forward RWW_OnFinished();

/**
 * Получение состояния разминки
 *
 * @return true, если разминка запущена, иначе false
 */
native bool:RWW_IsWarmupInProgress();
