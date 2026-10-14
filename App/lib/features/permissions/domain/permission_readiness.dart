import '../../../domain/entities/native_state.dart';

/// Permission readiness alone does not imply correction qualification.
bool hasKeyboardPermissions(NativeState state) =>
    state.capabilities['listen'] == true &&
    state.capabilities['post'] == true &&
    state.capabilities['axTrusted'] == true;
