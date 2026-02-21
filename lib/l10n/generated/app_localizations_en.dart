// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TrailShare';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get edit => 'Edit';

  @override
  String get create => 'Create';

  @override
  String get add => 'Add';

  @override
  String get send => 'Send';

  @override
  String get search => 'Search';

  @override
  String get share => 'Share';

  @override
  String get close => 'Close';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get ok => 'OK';

  @override
  String get loading => 'Loading...';

  @override
  String get retry => 'Retry';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get warning => 'Warning';

  @override
  String get select => 'Select';

  @override
  String get copy => 'Copy';

  @override
  String get continueAction => 'Continue';

  @override
  String get distance => 'Distance';

  @override
  String get elevation => 'Elevation';

  @override
  String get elevationGain => 'Elev. gain';

  @override
  String get elevationLoss => 'Elev. loss';

  @override
  String get duration => 'Duration';

  @override
  String get speed => 'Speed';

  @override
  String get avgSpeed => 'Avg speed';

  @override
  String get maxSpeed => 'Max speed';

  @override
  String get pace => 'Pace';

  @override
  String get altitude => 'Altitude';

  @override
  String get maxAltitude => 'Max alt.';

  @override
  String get minAltitude => 'Min alt.';

  @override
  String get totalDistance => 'Total distance';

  @override
  String get totalElevation => 'Total elevation';

  @override
  String get activity => 'Activity';

  @override
  String activityChanged(String type) {
    return 'Activity changed to $type';
  }

  @override
  String get details => 'Details';

  @override
  String get statistics => 'Statistics';

  @override
  String get statsPerKm => 'Stats per Km';

  @override
  String get photos => 'Photos';

  @override
  String get map => 'Map';

  @override
  String get track => 'Track';

  @override
  String get tracks => 'Tracks';

  @override
  String get myTracks => 'My tracks';

  @override
  String get noTracks => 'No tracks saved';

  @override
  String get trackSaved => 'Track saved!';

  @override
  String get trackDeleted => 'Track deleted';

  @override
  String get saveTrack => 'Save track';

  @override
  String get savingTrack => 'Saving track...';

  @override
  String get editTrack => 'Edit track';

  @override
  String get deleteTrack => 'Delete track';

  @override
  String get deleteTrackConfirm =>
      'Delete this track? This action cannot be undone.';

  @override
  String get publishTrack => 'Publish to community';

  @override
  String get removeFromCommunity => 'Remove from community';

  @override
  String get published => 'Published';

  @override
  String get trackName => 'Track name';

  @override
  String get noName => 'Unnamed';

  @override
  String get exportGpx => 'Export GPX';

  @override
  String exportError(String error) {
    return 'Export error: $error';
  }

  @override
  String get importGpx => 'Import GPX';

  @override
  String get planRoute => 'Plan route';

  @override
  String get plannedRoutes => 'Planned routes';

  @override
  String get recording => 'Recording';

  @override
  String get startRecording => 'Start recording';

  @override
  String get stopRecording => 'Stop recording';

  @override
  String get pauseRecording => 'Pause';

  @override
  String get resumeRecording => 'Resume';

  @override
  String get criticalBattery => 'Critical battery! Saving track...';

  @override
  String get gpsSignalLost => 'GPS signal lost';

  @override
  String get gpsSignalWeak => 'Weak GPS signal';

  @override
  String get recordingInProgress => 'Recording in progress';

  @override
  String get login => 'Log in';

  @override
  String get register => 'Sign up';

  @override
  String get logout => 'Log out';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String loginWith(String provider) {
    return 'Log in with $provider';
  }

  @override
  String get trackYourAdventures => 'Track your adventures';

  @override
  String get or => 'or';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get noAccount => 'Don\'t have an account?';

  @override
  String get registerNow => 'Sign up now';

  @override
  String get username => 'Username';

  @override
  String get chooseUsername => 'Choose your username';

  @override
  String get usernameHint => 'What should we call you?';

  @override
  String get usernameRequired => 'Username is required';

  @override
  String get usernameTooShort => 'At least 3 characters';

  @override
  String get usernameAlreadyTaken => 'Username already taken';

  @override
  String get profile => 'Profile';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get bio => 'Bio';

  @override
  String get level => 'Level';

  @override
  String get followers => 'Followers';

  @override
  String get following => 'Following';

  @override
  String get follow => 'Follow';

  @override
  String get unfollow => 'Unfollow';

  @override
  String get noFollowers => 'No followers';

  @override
  String get noFollowing => 'Not following anyone';

  @override
  String followersCount(int count) {
    return '$count followers';
  }

  @override
  String followingCount(int count) {
    return '$count following';
  }

  @override
  String get shareProfile => 'Share your hikes to get noticed!';

  @override
  String get discover => 'Discover';

  @override
  String get searchTrails => 'Search trails...';

  @override
  String get noTrailsInArea => 'No trails in this area';

  @override
  String get loadingFullTrack => 'Loading full track...';

  @override
  String get trailDetails => 'Trail details';

  @override
  String get deleteTrailAdmin => 'Delete trail (Admin)';

  @override
  String get difficulty => 'Difficulty';

  @override
  String get easy => 'Easy';

  @override
  String get moderate => 'Moderate';

  @override
  String get hard => 'Hard';

  @override
  String get community => 'Community';

  @override
  String get communityTracks => 'Community tracks';

  @override
  String get discoverGroups => 'Discover groups';

  @override
  String get suggestedUsers => 'People you may know';

  @override
  String get searchUsers => 'Search users';

  @override
  String get searchUsersHint => 'Search users with the bar above';

  @override
  String get noSuggestions => 'No suggestions at the moment';

  @override
  String get noResults => 'No results';

  @override
  String get groups => 'Groups';

  @override
  String get myGroups => 'My groups';

  @override
  String get group => 'Group';

  @override
  String get createGroup => 'Create group';

  @override
  String get joinGroup => 'Join';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get deleteGroupConfirm =>
      'Delete this group? This action cannot be undone.';

  @override
  String get groupName => 'Group name';

  @override
  String get groupDescription => 'Group description';

  @override
  String get members => 'Members';

  @override
  String membersCount(int count) {
    return '$count members';
  }

  @override
  String get admin => 'Admin';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get inviteCodeHint => 'Enter invite code';

  @override
  String get joinWithCode => 'Join with code';

  @override
  String get visibility => 'Visibility';

  @override
  String get public => 'Public';

  @override
  String get privateGroup => 'Private';

  @override
  String get secret => 'Secret';

  @override
  String get publicDesc => 'Visible to everyone, anyone can join';

  @override
  String get privateDesc => 'Visible to everyone, access on request';

  @override
  String get secretDesc => 'Invisible, invite code only';

  @override
  String get requestAccess => 'Request access';

  @override
  String get requestSent => 'Request sent!';

  @override
  String get requestAlreadySent => 'You already sent a request';

  @override
  String get pendingRequests => 'Access requests';

  @override
  String get approveRequest => 'Approve';

  @override
  String get rejectRequest => 'Reject';

  @override
  String get requestApproved => 'Request approved';

  @override
  String get requestRejected => 'Request rejected';

  @override
  String get groupVisibility => 'Group visibility';

  @override
  String get chat => 'Chat';

  @override
  String get messages => 'Messages';

  @override
  String get noMessages => 'No messages';

  @override
  String get startConversation => 'Start the conversation!';

  @override
  String get writeMessage => 'Write a message...';

  @override
  String get sendingImage => 'Sending image...';

  @override
  String get imageUploadError => 'Image upload error';

  @override
  String get events => 'Events';

  @override
  String get createEvent => 'Create event';

  @override
  String get eventTitle => 'Event title';

  @override
  String get eventDate => 'Date';

  @override
  String get eventTime => 'Time';

  @override
  String get eventDescription => 'Details about the outing...';

  @override
  String get eventDistance => 'Distance';

  @override
  String get eventElevation => 'Elevation';

  @override
  String get maxParticipants => 'Max participants';

  @override
  String get noLimit => 'No limit';

  @override
  String get join => 'Join';

  @override
  String get leave => 'Leave';

  @override
  String get participants => 'Participants';

  @override
  String get noEvents => 'No upcoming events';

  @override
  String get upcomingEvents => 'Upcoming events';

  @override
  String get challenges => 'Challenges';

  @override
  String get createChallenge => 'Create challenge';

  @override
  String get challengeTitle => 'Challenge title';

  @override
  String get noParticipants => 'No participants yet';

  @override
  String get leaderboard => 'Leaderboard';

  @override
  String get activeChallenges => 'Active challenges';

  @override
  String get completedChallenges => 'Completed challenges';

  @override
  String get challengeType => 'Challenge type';

  @override
  String get distanceChallenge => 'Distance';

  @override
  String get elevationChallenge => 'Elevation';

  @override
  String get tracksChallenge => 'Tracks';

  @override
  String get streakChallenge => 'Streak';

  @override
  String get settings => 'Settings';

  @override
  String get generalSettings => 'General';

  @override
  String get mapSettings => 'Maps';

  @override
  String get notificationSettings => 'Notifications';

  @override
  String get account => 'Account';

  @override
  String get theme => 'Theme';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get lightMode => 'Light mode';

  @override
  String get systemMode => 'Follow system';

  @override
  String get language => 'Language';

  @override
  String get offlineMaps => 'Offline maps';

  @override
  String get downloadMap => 'Download map';

  @override
  String get deleteMap => 'Delete map';

  @override
  String get mapDownloaded => 'Map downloaded';

  @override
  String get storageUsed => 'Storage used';

  @override
  String get units => 'Units';

  @override
  String get metric => 'Metric (km, m)';

  @override
  String get imperial => 'Imperial (mi, ft)';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfService => 'Terms of service';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountConfirm =>
      'Delete your account? All data will be lost.';

  @override
  String get liveTracking => 'Live tracking';

  @override
  String durationLabel(String duration) {
    return 'Duration: $duration';
  }

  @override
  String get wishlistAdded => 'Saved';

  @override
  String get wishlistRemoved => 'Removed';

  @override
  String get saved => 'Saved';

  @override
  String get saving => 'Saving...';

  @override
  String get errorGeneric => 'An error occurred';

  @override
  String get errorUnknown => 'Unknown error';

  @override
  String get errorNetwork => 'Connection error';

  @override
  String get errorPermission => 'Permission denied';

  @override
  String get noData => 'No data';

  @override
  String get noUser => 'No user';

  @override
  String get greatJob => 'Great job! 💪';

  @override
  String get greatHike => 'Amazing hike! 🏔️';

  @override
  String get fantasticTrail => 'Fantastic trail! 🥾';

  @override
  String get whatAdventure => 'What an adventure! 🌟';

  @override
  String get trueExplorer => 'You\'re a true explorer! 🧭';

  @override
  String get trailCompleted => 'Trail completed! 🎯';

  @override
  String get keepItUp => 'Well done, keep it up! 🔥';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get km => 'km';

  @override
  String get m => 'm';

  @override
  String get h => 'h';

  @override
  String get min => 'min';

  @override
  String get info => 'Info';

  @override
  String get sharedTracks => 'Shared tracks';

  @override
  String get name => 'Name';

  @override
  String get description => 'Description';

  @override
  String get adminPanel => 'Admin panel';

  @override
  String get noUsersFound => 'No users';

  @override
  String get noResultsFound => 'No results';

  @override
  String get databaseStats => 'Database stats';

  @override
  String get tapKmToHighlight => 'Tap a km to highlight it on the map';

  @override
  String get total => 'TOT';
}
