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
  String get noName => 'No name';

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
  String get recording => 'RECORDING';

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
  String get createGroup => 'Create Group';

  @override
  String get joinGroup => 'Join';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String deleteGroupConfirm(String name) {
    return 'Do you want to delete \"$name\"?\n\nThis action is irreversible.';
  }

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
  String get offlineMaps => 'Offline Maps';

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
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get deleteAccount => 'Delete Account';

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
  String get databaseStats => 'Database Stats';

  @override
  String get tapKmToHighlight => 'Tap a km to highlight it on the map';

  @override
  String get total => 'TOT';

  @override
  String get defaultUser => 'User';

  @override
  String get usernameUpdated => 'Username updated!';

  @override
  String get bioUpdated => 'Bio updated!';

  @override
  String errorWithDetails(String error) {
    return 'Error: $error';
  }

  @override
  String get logoutConfirm => 'Do you want to log out?';

  @override
  String get loginToSeeProfile => 'Log in to see your profile';

  @override
  String get loginProfileDescription =>
      'Save your tracks, follow other hikers and much more.';

  @override
  String get editNickname => 'Edit nickname';

  @override
  String get bioHint => 'Tell us about yourself...';

  @override
  String get addBio => 'Add a bio';

  @override
  String get editBio => 'Edit bio';

  @override
  String levelNumber(int level) {
    return 'Level $level';
  }

  @override
  String get myContacts => 'My contacts';

  @override
  String contactsSummary(int followers, int following) {
    return '$followers followers · $following following';
  }

  @override
  String get viewDashboard => 'View Dashboard';

  @override
  String get savedRoutes => 'Saved Routes';

  @override
  String get weeklyLeaderboard => 'Weekly Leaderboard';

  @override
  String get myBadges => 'My Badges';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get noStatsAvailable => 'No statistics available';

  @override
  String get recordFirstTrackForStats =>
      'Record your first track to see statistics!';

  @override
  String get summary => 'Summary';

  @override
  String get totalTracksLabel => 'Total Tracks';

  @override
  String get totalTime => 'Total Time';

  @override
  String get personalRecords => 'Personal Records';

  @override
  String get longestTrack => 'Longest track';

  @override
  String get highestElevationRecord => 'Highest elevation gain';

  @override
  String get longestDuration => 'Longest duration';

  @override
  String get activityDistribution => 'Activity Distribution';

  @override
  String get trend => 'Trend';

  @override
  String get week => 'Week';

  @override
  String get month => 'Month';

  @override
  String get year => 'Year';

  @override
  String get noDataForPeriod => 'No data for this period';

  @override
  String get thisWeek => 'This Week';

  @override
  String get previousWeek => 'Previous Week';

  @override
  String get noRecord => 'No record';

  @override
  String get activityCycling => 'Cycling';

  @override
  String get activityWalking => 'Walking';

  @override
  String get daySun => 'Sun';

  @override
  String get dayMon => 'Mon';

  @override
  String get dayTue => 'Tue';

  @override
  String get dayWed => 'Wed';

  @override
  String get dayThu => 'Thu';

  @override
  String get dayFri => 'Fri';

  @override
  String get daySat => 'Sat';

  @override
  String get monthJanShort => 'Jan';

  @override
  String get monthFebShort => 'Feb';

  @override
  String get monthMarShort => 'Mar';

  @override
  String get monthAprShort => 'Apr';

  @override
  String get monthMayShort => 'May';

  @override
  String get monthJunShort => 'Jun';

  @override
  String get monthJulShort => 'Jul';

  @override
  String get monthAugShort => 'Aug';

  @override
  String get monthSepShort => 'Sep';

  @override
  String get monthOctShort => 'Oct';

  @override
  String get monthNovShort => 'Nov';

  @override
  String get monthDecShort => 'Dec';

  @override
  String get monthJan => 'January';

  @override
  String get monthFeb => 'February';

  @override
  String get monthMar => 'March';

  @override
  String get monthApr => 'April';

  @override
  String get monthMay => 'May';

  @override
  String get monthJun => 'June';

  @override
  String get monthJul => 'July';

  @override
  String get monthAug => 'August';

  @override
  String get monthSep => 'September';

  @override
  String get monthOct => 'October';

  @override
  String get monthNov => 'November';

  @override
  String get monthDec => 'December';

  @override
  String activeTabCount(int count) {
    return 'Active ($count)';
  }

  @override
  String myChallengesTabCount(int count) {
    return 'Mine ($count)';
  }

  @override
  String get createChallengeBtn => 'Create Challenge';

  @override
  String get noActiveChallenges => 'No active challenges';

  @override
  String get notInAnyChallenges => 'You haven\'t joined any challenges';

  @override
  String get createFirstChallenge =>
      'Create the first challenge and challenge the community!';

  @override
  String get joinFromActiveTab => 'Join a challenge from the \"Active\" tab';

  @override
  String joinChallengeTitle(String title) {
    return 'Join \"$title\"';
  }

  @override
  String get goalLabel => 'Goal';

  @override
  String get deadlineLabel => 'Deadline';

  @override
  String daysCount(int days) {
    return '$days days';
  }

  @override
  String get joinChallengeConfirm => 'Do you want to join this challenge?';

  @override
  String get joinAction => 'Join';

  @override
  String get joinedChallenge => '🎉 You joined the challenge!';

  @override
  String get joinError => 'Error joining the challenge';

  @override
  String get challengeDetail => 'Challenge Detail';

  @override
  String createdBy(String name) {
    return 'Created by $name';
  }

  @override
  String get yourProgress => 'Your progress';

  @override
  String get enrolled => '✓ Enrolled';

  @override
  String participantsCount(int count) {
    return '$count participants';
  }

  @override
  String goalPrefix(String goal) {
    return 'Goal: $goal';
  }

  @override
  String get createNewChallenge => 'Create a new challenge';

  @override
  String get challengeHint => 'E.g.: 100km in a week';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get describeChallenge => 'Describe the challenge...';

  @override
  String get challengeTypeLabel => 'Challenge type';

  @override
  String get enterTitle => 'Enter a title';

  @override
  String get enterGoal => 'Enter a goal';

  @override
  String get enterValidNumber => 'Enter a valid number';

  @override
  String get challengeCreated => '🎉 Challenge created!';

  @override
  String get creationError => 'Error during creation';

  @override
  String get tracksUnit => 'tracks';

  @override
  String get newBadge => 'New Badge!';

  @override
  String get fantastic => 'Fantastic!';

  @override
  String get badges => 'Badges';

  @override
  String unlockedCount(int count) {
    return 'Unlocked ($count)';
  }

  @override
  String allCount(int count) {
    return 'All ($count)';
  }

  @override
  String get noBadgesYet => 'No badges yet';

  @override
  String get completeTracksForBadges =>
      'Complete tracks and activities to unlock badges!';

  @override
  String get viewAllBadges => 'View all badges';

  @override
  String get milestones => 'Milestones';

  @override
  String get socialCategory => 'Social';

  @override
  String get streakCategory => 'Streak';

  @override
  String unlockedOn(String date) {
    return 'Unlocked on $date';
  }

  @override
  String get leaderboardLoadError => 'Error loading leaderboard';

  @override
  String get yourPosition => 'Your position';

  @override
  String get youAreLeading => '🏆 You\'re in the lead!';

  @override
  String positionOfTotal(int rank, int total) {
    return 'Position $rank of $total';
  }

  @override
  String get noActivityThisWeek => 'No activity this week';

  @override
  String get completeTrackForLeaderboard =>
      'Complete a track to appear in the leaderboard.\nFollow other users to compete with them!';

  @override
  String get startHike => 'Start a hike';

  @override
  String get loginToSeeLeaderboard => 'Log in to see the leaderboard';

  @override
  String get competeWithFriends =>
      'Compete with friends and climb the weekly leaderboard!';

  @override
  String get youLabel => 'YOU';

  @override
  String xpThisWeek(int xp) {
    return '$xp XP this week';
  }

  @override
  String get accountSection => 'Account';

  @override
  String get emailLabel => 'Email';

  @override
  String get notAvailable => 'Not available';

  @override
  String get signOutTitle => 'Sign out';

  @override
  String get signOutSubtitle => 'Disconnect your account';

  @override
  String get signOutConfirm => 'Do you want to sign out?';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get healthConnectionSection => 'Health Connection';

  @override
  String get syncWithHealth => 'Sync with Health';

  @override
  String get saveToAppleHealth => 'Save activities to Apple Health';

  @override
  String get saveToHealthConnect => 'Save activities to Health Connect';

  @override
  String get healthConnectRequired => 'Health Connect required';

  @override
  String get healthConnectInstallMessage =>
      'Health Connect is required to sync activities. You can install it from the Play Store.\n\nDo you want to install it now?';

  @override
  String get installAction => 'Install';

  @override
  String get permissionsNotGranted =>
      'Permissions not granted. Try again or enable them from device settings.';

  @override
  String get maxHeartRate => 'Maximum heart rate';

  @override
  String get maxHRDescription =>
      'Enter your max HR if you know it, or enter your age to estimate it (220 - age).';

  @override
  String get maxHRLabel => 'Max HR (BPM)';

  @override
  String get maxHRHint => 'E.g.: 185';

  @override
  String get orLabel => 'or';

  @override
  String get ageLabel => 'Age';

  @override
  String get ageHint => 'E.g.: 35';

  @override
  String get setForCardioZones => 'Set to calculate cardio zones';

  @override
  String get healthDashboard => 'Health Dashboard';

  @override
  String get healthDashboardSubtitle => 'Steps, heart rate, weekly calories';

  @override
  String get legalSection => 'Legal';

  @override
  String get privacyPolicySubtitle => 'How we handle your data';

  @override
  String get termsOfServiceSubtitle => 'App terms and conditions';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get openSourceLicensesSubtitle => 'Libraries used';

  @override
  String get supportSection => 'Support';

  @override
  String get helpCenter => 'Help Center';

  @override
  String get helpCenterSubtitle => 'FAQ and guides';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get rateApp => 'Rate the app';

  @override
  String get rateAppSubtitle => 'Leave a review';

  @override
  String get offlineMapsSubtitle => 'Download maps for offline use';

  @override
  String get infoSection => 'Information';

  @override
  String get versionLabel => 'Version';

  @override
  String get loadingEllipsis => 'Loading...';

  @override
  String get whatsNew => 'What\'s New';

  @override
  String get whatsNewSubtitle => 'See what\'s new';

  @override
  String get adminSection => 'Administration';

  @override
  String get importTrails => 'Import Trails';

  @override
  String get importTrailsSubtitle => 'Import trails from Waymarked Trails';

  @override
  String get geohashMigration => 'GeoHash Migration';

  @override
  String get geohashMigrationSubtitle => 'Manage geospatial indexes for trails';

  @override
  String get databaseStatsSubtitle => 'View metrics and usage';

  @override
  String get recalculateStats => 'Recalculate Stats';

  @override
  String get recalculateStatsSubtitle =>
      'Fix elevation and distances from GPS tracks';

  @override
  String get dangerZone => 'Danger Zone';

  @override
  String get deleteAccountSubtitle => 'Permanently delete all your data';

  @override
  String get accountDeleted => 'Account deleted successfully';

  @override
  String get cannotOpenLink => 'Cannot open link';

  @override
  String get cannotOpenEmail => 'Cannot open email client';

  @override
  String get appComingSoon =>
      'Thank you! The app will be available soon in the stores.';

  @override
  String get changelogTitle => 'What\'s new v1.0.0';

  @override
  String get changelogFirstRelease => '🎉 First release!';

  @override
  String get changelogGpsTracking => 'GPS track recording';

  @override
  String get changelogBackground => 'Background tracking';

  @override
  String get changelogLiveTrack => 'LiveTrack - share position';

  @override
  String get changelogSocial => 'Social system (follow, cheers)';

  @override
  String get changelogLeaderboard => 'Weekly leaderboard';

  @override
  String get changelogWishlist => 'Trail wishlist';

  @override
  String get changelogDashboard => 'Statistics dashboard';

  @override
  String get changelogGpx => 'GPX Import/Export';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeAutomatic => 'Automatic';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get selectTheme => 'Select theme';

  @override
  String get themeAutomaticSubtitle => 'Follows system settings';

  @override
  String get themeLightSubtitle => 'Light theme always on';

  @override
  String get themeDarkSubtitle => 'Dark theme always on';

  @override
  String get stepsToday => 'Steps today';

  @override
  String get restingHR => 'Resting HR';

  @override
  String get goalReached => '🎉 Goal reached!';

  @override
  String percentOfGoal(int pct) {
    return '$pct% of 10,000';
  }

  @override
  String get stepsLast7Days => 'Steps — Last 7 days';

  @override
  String get caloriesLast7Days => 'Calories — Last 7 days';

  @override
  String get noStepsData => 'No steps data available';

  @override
  String get noCaloriesData => 'No calories data available';

  @override
  String get stepsUnit => 'steps';

  @override
  String get healthDataInfo =>
      'Data comes from your smartwatch via Health Connect. Make sure your device is synced for up-to-date data.';

  @override
  String get faqHowCanWeHelp => 'How can we help you?';

  @override
  String get faqFindAnswers => 'Find answers to frequently asked questions';

  @override
  String get faqCategoryGeneral => '📱 General';

  @override
  String get faqCategoryTracking => '🗺️ GPS Tracking';

  @override
  String get faqCategorySocial => '👥 Social';

  @override
  String get faqCategoryGamification => '🏆 Gamification';

  @override
  String get faqCategoryTechnical => '⚙️ Technical';

  @override
  String get faqNoAnswer => 'Didn\'t find your answer?';

  @override
  String get faqContactPrompt =>
      'Contact us and we\'ll get back to you shortly';

  @override
  String get faqContactSupport => 'Contact support';

  @override
  String get faqGeneralQ1 => 'What is TrailShare?';

  @override
  String get faqGeneralA1 =>
      'TrailShare is an app for recording and sharing your hikes. You can track your routes with GPS, discover new trails, follow other hikers and join weekly challenges.';

  @override
  String get faqGeneralQ2 => 'Is the app free?';

  @override
  String get faqGeneralA2 =>
      'Yes, TrailShare is completely free. All features are available with no hidden costs or subscriptions.';

  @override
  String get faqGeneralQ3 => 'Do I need to create an account?';

  @override
  String get faqGeneralA3 =>
      'Yes, an account is required to save your tracks and access social features. You can sign up with email, Google or Apple.';

  @override
  String get faqGeneralQ4 => 'Is my data safe?';

  @override
  String get faqGeneralA4 =>
      'Absolutely. Your data is protected and encrypted. You can check our Privacy Policy for full details on how we handle your information.';

  @override
  String get faqTrackingQ1 => 'How do I record a track?';

  @override
  String get faqTrackingA1 =>
      'Go to the \"Record\" section, tap the green \"Start\" button and walk! The app will automatically record your route. You can pause and resume at any time.';

  @override
  String get faqTrackingQ2 => 'Does GPS work in the background?';

  @override
  String get faqTrackingA2 =>
      'Yes, you can lock the screen or use other apps while recording. Tracking continues in the background with an active notification.';

  @override
  String get faqTrackingQ3 => 'How much battery does it use?';

  @override
  String get faqTrackingA3 =>
      'Battery usage depends on the hike duration. On average, expect 5-10% per hour. We recommend starting with a full charge or bringing a power bank.';

  @override
  String get faqTrackingQ4 => 'Does it work without internet?';

  @override
  String get faqTrackingA4 =>
      'Yes! GPS tracking works completely offline. You can also download maps in advance from Settings > Offline Maps. Sync will happen when you\'re back online.';

  @override
  String get faqTrackingQ5 => 'How do I improve GPS accuracy?';

  @override
  String get faqTrackingA5 =>
      'Make sure you have a clear view of the sky. Avoid areas with dense cover or narrow canyons. Wait a few seconds before starting to let the GPS calibrate.';

  @override
  String get faqTrackingQ6 => 'Can I import GPX tracks?';

  @override
  String get faqTrackingA6 =>
      'Yes, you can import GPX files from the \"My Tracks\" section. Tap the + button and select \"Import GPX\".';

  @override
  String get faqTrackingQ7 => 'Can I export my tracks?';

  @override
  String get faqTrackingA7 =>
      'Of course! Open a track and tap the share icon to export it in GPX format, compatible with most apps and GPS devices.';

  @override
  String get faqSocialQ1 => 'How do I follow other users?';

  @override
  String get faqSocialA1 =>
      'Search for a user or visit their profile from a public track, then tap \"Follow\". You\'ll see their new tracks in your feed.';

  @override
  String get faqSocialQ2 => 'What is a \"Cheers\"?';

  @override
  String get faqSocialA2 =>
      'It\'s our way of saying \"nice track!\". You can leave a cheers on tracks you like. You\'ll also earn XP for cheers received.';

  @override
  String get faqSocialQ3 => 'How do I publish a track?';

  @override
  String get faqSocialA3 =>
      'After saving a track, open it and tap \"Publish\". The track will be visible in the Explore section and others will be able to see it.';

  @override
  String get faqSocialQ4 => 'Can I make a track private?';

  @override
  String get faqSocialA4 =>
      'Tracks are private by default. Only those you explicitly publish will be visible to others.';

  @override
  String get faqSocialQ5 => 'What is LiveTrack?';

  @override
  String get faqSocialA5 =>
      'LiveTrack lets you share your position in real time during a hike. It generates a link you can send to family or friends so they can follow you on the map.';

  @override
  String get faqGamificationQ1 => 'How do XP work?';

  @override
  String get faqGamificationA1 =>
      'You earn XP (experience points) by completing tracks, receiving cheers, gaining followers and completing challenges. The more XP you accumulate, the higher your level!';

  @override
  String get faqGamificationQ2 => 'How many levels are there?';

  @override
  String get faqGamificationA2 =>
      'There are 20 levels, from \"Beginner\" to \"Immortal\". Each level requires more XP than the previous one.';

  @override
  String get faqGamificationQ3 => 'How do I unlock badges?';

  @override
  String get faqGamificationA3 =>
      'Badges are unlocked automatically when you reach certain milestones: km traveled, elevation gained, consecutive activity days and social goals.';

  @override
  String get faqGamificationQ4 => 'How does the leaderboard work?';

  @override
  String get faqGamificationA4 =>
      'The weekly leaderboard is based on km traveled and elevation gained during the week. It resets every Monday.';

  @override
  String get faqGamificationQ5 => 'Can I see other users\' badges?';

  @override
  String get faqGamificationA5 =>
      'Yes, by visiting a user\'s profile you can see their unlocked badges and their level.';

  @override
  String get faqTechnicalQ1 => 'How do I connect a heart rate monitor?';

  @override
  String get faqTechnicalA1 =>
      'During recording, tap the heart icon at the top. The app will automatically search for nearby Bluetooth heart rate monitors. Select yours to connect.';

  @override
  String get faqTechnicalQ2 => 'Which heart rate monitors are compatible?';

  @override
  String get faqTechnicalA2 =>
      'TrailShare supports any standard Bluetooth Low Energy (BLE) heart rate monitor, such as Polar H10, Garmin HRM-Dual, Wahoo TICKR and many others.';

  @override
  String get faqTechnicalQ3 => 'How do I download offline maps?';

  @override
  String get faqTechnicalA3 =>
      'Go to Settings > Offline Maps > Download Area. Select the area on the map, choose the detail level and start the download.';

  @override
  String get faqTechnicalQ4 => 'How much space do offline maps take?';

  @override
  String get faqTechnicalA4 =>
      'It depends on the area and zoom level. A 10km area with medium zoom takes about 30-50 MB. You can check used space in settings.';

  @override
  String get faqTechnicalQ5 => 'How do I change light/dark theme?';

  @override
  String get faqTechnicalA5 =>
      'Go to Settings > Appearance > Theme. You can choose between Light, Dark or Automatic (follows system settings).';

  @override
  String get faqTechnicalQ6 => 'How do I delete my account?';

  @override
  String get faqTechnicalA6 =>
      'Go to Settings > Danger Zone > Delete Account. You\'ll need to confirm with your password. This action is irreversible and will delete all your data.';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get downloadArea => 'Download Area';

  @override
  String areasCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count areas',
      one: '1 area',
    );
    return '$_temp0';
  }

  @override
  String get noOfflineMaps => 'No offline maps';

  @override
  String get downloadMapsForOffline =>
      'Download maps to use them when you\'re offline';

  @override
  String get areaName => 'Area name';

  @override
  String get areaNameHint => 'E.g.: Dolomites, Alps...';

  @override
  String minZoomLabel(int value) {
    return 'Min zoom: $value';
  }

  @override
  String maxZoomLabel(int value) {
    return 'Max zoom: $value';
  }

  @override
  String get tilesToDownload => 'Tiles to download:';

  @override
  String get estimatedSize => 'Estimated size:';

  @override
  String get downloadAction => 'Download';

  @override
  String get deleteArea => 'Delete area';

  @override
  String deleteAreaConfirm(String name) {
    return 'Do you want to delete \"$name\"?';
  }

  @override
  String get deleteLabel => 'Delete';

  @override
  String get deleteAllMaps => 'Delete all maps';

  @override
  String get deleteAllMapsConfirm =>
      'Do you want to delete all offline maps? This action cannot be undone.';

  @override
  String get deleteAllAction => 'Delete all';

  @override
  String get selectArea => 'Select Area';

  @override
  String get confirmAction => 'Confirm';

  @override
  String get tapMapToSelectCenter => 'Tap the map to select the center';

  @override
  String get radiusLabel => 'Radius:';

  @override
  String get downloadCompleted => '✓ Completed!';

  @override
  String get downloadInProgress => 'Downloading...';

  @override
  String tileProgress(int downloaded, int total) {
    return '$downloaded / $total tiles';
  }

  @override
  String get closeAction => 'Close';

  @override
  String get privacyLastUpdated => 'Last updated: January 2025';

  @override
  String get privacyIntroTitle => 'Introduction';

  @override
  String get privacyIntroContent =>
      'TrailShare (\"we\", \"our\" or \"app\") respects your privacy. This policy describes what data we collect, how we use it and your rights.';

  @override
  String get privacyDataCollectedTitle => 'Data we collect';

  @override
  String get privacyDataCollectedContent =>
      '• **Registration data**: email, username, profile photo (optional)\n• **Location data**: GPS coordinates during track recording\n• **Activity data**: recorded tracks, statistics, elevation, distance\n• **Social data**: followers, following, \"cheers\" (likes)\n• **Device data**: model, operating system, to improve the app';

  @override
  String get privacyDataUsageTitle => 'How we use your data';

  @override
  String get privacyDataUsageContent =>
      '• Provide and improve app services\n• Save and sync your tracks\n• Enable social features (follow, cheers, leaderboard)\n• LiveTrack feature to share your position in real time\n• Aggregate analytics to improve user experience';

  @override
  String get privacyDataSharingTitle => 'Data sharing';

  @override
  String get privacyDataSharingContent =>
      '• **We do not sell** your personal data to third parties\n• Published tracks are visible to other users\n• LiveTrack shares your position only with those who have the link\n• We use Firebase (Google) for secure data storage';

  @override
  String get privacyRetentionTitle => 'Data retention';

  @override
  String get privacyRetentionContent =>
      'Your data is retained as long as you maintain an active account. You can delete your account at any time from Settings, and all your data will be removed within 30 days.';

  @override
  String get privacyRightsTitle => 'Your rights';

  @override
  String get privacyRightsContent =>
      '• **Access**: you can view all your data in the app\n• **Edit**: you can edit your profile at any time\n• **Deletion**: you can delete your account and all associated data\n• **Export**: you can export your tracks in GPX format';

  @override
  String get privacySecurityTitle => 'Security';

  @override
  String get privacySecurityContent =>
      'We use Firebase Authentication and Firestore with encryption to protect your data. Connections are secured via HTTPS.';

  @override
  String get privacyMinorsTitle => 'Minors';

  @override
  String get privacyMinorsContent =>
      'The app is not intended for children under 13. We do not knowingly collect data from children under this age.';

  @override
  String get privacyChangesTitle => 'Policy changes';

  @override
  String get privacyChangesContent =>
      'We may update this privacy policy. We will notify you of any significant changes through the app or email.';

  @override
  String get privacyContactTitle => 'Contact';

  @override
  String get privacyContactContent =>
      'For privacy questions, contact us at:\n📧 privacy@trailshare.app';

  @override
  String get viewWebVersion => 'View web version';

  @override
  String get searchByUsername => 'Search by username...';

  @override
  String noUserFoundFor(String query) {
    return 'No user found for \"$query\"';
  }

  @override
  String get tryDifferentUsername => 'Try a different username';

  @override
  String get peopleYouMayKnow => 'People you may know';

  @override
  String get noSuggestionsNow => 'No suggestions at the moment';

  @override
  String get searchUsersAbove => 'Search users with the bar above';

  @override
  String levelLabel(int level) {
    return 'Level $level';
  }

  @override
  String followersOf(String name) {
    return '$name\'s followers';
  }

  @override
  String followedBy(String name) {
    return 'Followed by $name';
  }

  @override
  String get noFollowersYet => 'No followers yet';

  @override
  String get notFollowingAnyone => 'Not following anyone';

  @override
  String get shareHikesToGetKnown => 'Share your hikes to get noticed!';

  @override
  String get exploreCommunity =>
      'Explore the community to find interesting people.';

  @override
  String get skipAction => 'Skip';

  @override
  String get startAction => 'Let\'s go!';

  @override
  String get nextAction => 'Next';

  @override
  String get onboardingWelcomeTitle => 'Welcome to TrailShare';

  @override
  String get onboardingWelcomeDesc =>
      'Your app for recording and sharing outdoor adventures. Track your routes, discover new trails and connect with other hikers.';

  @override
  String get onboardingTrackTitle => 'Track your routes';

  @override
  String get onboardingTrackDesc =>
      'Record your hikes with precise GPS. View distance, elevation, speed and time in real time, even in the background.';

  @override
  String get onboardingExploreTitle => 'Discover new trails';

  @override
  String get onboardingExploreDesc =>
      'Explore routes published by the community. Save your favorites to your wishlist and plan your next adventure.';

  @override
  String get onboardingConnectTitle => 'Connect with others';

  @override
  String get onboardingConnectDesc =>
      'Follow friends and hikers, share your routes and climb the weekly leaderboard. Earn XP and unlock badges!';

  @override
  String get onboardingOfflineTitle => 'Works offline too';

  @override
  String get onboardingOfflineDesc =>
      'Download maps to use without a connection. GPS tracking always works, even in airplane mode.';

  @override
  String get chooseYourUsername => 'Choose your username';

  @override
  String get usernameVisibleToOthers =>
      'This name will be visible to other TrailShare users';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameExampleHint => 'e.g. john_doe';

  @override
  String get usernameRules =>
      '3-20 characters • Letters, numbers, dots and underscores';

  @override
  String get enterUsername => 'Enter a username';

  @override
  String get usernameMinChars => 'Minimum 3 characters';

  @override
  String get usernameMaxChars => 'Maximum 20 characters';

  @override
  String get usernameInvalidChars =>
      'Only letters, numbers, dots and underscores';

  @override
  String get usernameAlreadyTakenChooseAnother =>
      'Username already taken, choose another one';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orDivider => 'or';

  @override
  String get enterYourEmail => 'Enter your email';

  @override
  String get invalidEmail => 'Invalid email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get enterPassword => 'Enter your password';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get enterEmailForReset =>
      'Enter your email to receive the reset link.';

  @override
  String get sendAction => 'Send';

  @override
  String get resetEmailSent => 'Reset email sent!';

  @override
  String get genericError => 'Error';

  @override
  String get loginAction => 'Log in';

  @override
  String get noAccountQuestion => 'Don\'t have an account?';

  @override
  String get registerAction => 'Sign up';

  @override
  String get loginCancelled => 'Login cancelled';

  @override
  String get createAccount => 'Create account';

  @override
  String get joinTrailShare => 'Join TrailShare';

  @override
  String get createAccountToSaveTracks =>
      'Create an account to save your tracks';

  @override
  String get orRegisterWithEmail => 'or register with email';

  @override
  String get enterAPassword => 'Enter a password';

  @override
  String get passwordMinSixChars => 'Minimum 6 characters';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get confirmYourPassword => 'Confirm your password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get accountCreatedSuccess => '✅ Account created successfully!';

  @override
  String get acceptTermsAndPrivacy =>
      'By creating an account you agree to our Terms of Service and Privacy Policy';

  @override
  String tracksTabCount(int count) {
    return 'Tracks ($count)';
  }

  @override
  String groupsTabCount(int count) {
    return 'Groups ($count)';
  }

  @override
  String eventsTabCount(int count) {
    return 'Events ($count)';
  }

  @override
  String get showList => 'Show list';

  @override
  String get showMap => 'Show map';

  @override
  String get searchTracksOrUsers => 'Search tracks or users...';

  @override
  String get noSharedTracks => 'No shared tracks';

  @override
  String noResultsForQuery(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get tracksLabel => 'tracks';

  @override
  String get loadMore => 'Load more';

  @override
  String get loadMoreTracks => 'Load more tracks';

  @override
  String get newGroup => 'New Group';

  @override
  String myFilterCount(int count) {
    return 'Mine ($count)';
  }

  @override
  String get discoverFilter => 'Discover';

  @override
  String get codeLabel => 'Code';

  @override
  String get noGroups => 'No groups';

  @override
  String get createGroupCTA =>
      'Create a group to organize outings, launch challenges and chat with your adventure companions!';

  @override
  String get noGroupsAvailable => 'No groups available';

  @override
  String get noPublicGroupsCTA =>
      'There are no public groups to join at the moment. Create one yourself!';

  @override
  String memberCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get publicLabel => 'Public';

  @override
  String get privateLabel => 'Private';

  @override
  String get secretLabel => 'Secret';

  @override
  String joinedGroupSnack(String name) {
    return 'You joined \"$name\"!';
  }

  @override
  String get joinGroupAction => 'Join';

  @override
  String requestSentSnack(String name) {
    return 'Request sent to \"$name\"!';
  }

  @override
  String get requestAction => 'Request';

  @override
  String get publicEventsFilter => 'Public';

  @override
  String activeChallengesCount(int count) {
    return 'Active challenges ($count)';
  }

  @override
  String get noEventsScheduled => 'No events scheduled';

  @override
  String get groupEventsWillAppear =>
      'Events from your groups will appear here';

  @override
  String get noPublicEvents => 'No public events';

  @override
  String get publicEventsWillAppear =>
      'Events from public groups will appear here';

  @override
  String get participating => '✓ Joined';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get enterInviteCodeDesc =>
      'Enter the invite code you received to join a group.';

  @override
  String get codeMustBeSixChars => 'Code must be 6 characters';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get joinedGroupGeneric => 'You joined the group!';

  @override
  String daysShort(int days) {
    return '${days}d';
  }

  @override
  String get monthShortJan => 'JAN';

  @override
  String get monthShortFeb => 'FEB';

  @override
  String get monthShortMar => 'MAR';

  @override
  String get monthShortApr => 'APR';

  @override
  String get monthShortMay => 'MAY';

  @override
  String get monthShortJun => 'JUN';

  @override
  String get monthShortJul => 'JUL';

  @override
  String get monthShortAug => 'AUG';

  @override
  String get monthShortSep => 'SEP';

  @override
  String get monthShortOct => 'OCT';

  @override
  String get monthShortNov => 'NOV';

  @override
  String get monthShortDec => 'DEC';

  @override
  String leaveGroupConfirm(String name) {
    return 'Do you want to leave \"$name\"?';
  }

  @override
  String get exitAction => 'Exit';

  @override
  String get deleteAction => 'Delete';

  @override
  String get membersLabel => 'Members';

  @override
  String get chatTab => 'Chat';

  @override
  String get eventsTab => 'Events';

  @override
  String get challengesTab => 'Challenges';

  @override
  String get infoTab => 'Info';

  @override
  String get inviteCodeTitle => 'Invite Code';

  @override
  String get regenerateCode => 'Regenerate code';

  @override
  String get shareInviteCodeDesc =>
      'Share this code to invite new people to the group';

  @override
  String get publicVisibilityDesc => 'Visible, anyone can join';

  @override
  String get privateVisibilityDesc => 'Visible, request to join';

  @override
  String get secretVisibilityDesc => 'Hidden, invite code only';

  @override
  String get accessRequests => 'Access requests';

  @override
  String requestedOnDate(String date) {
    return 'Requested on $date';
  }

  @override
  String get pendingStatus => 'Pending';

  @override
  String userApproved(String username) {
    return '$username approved!';
  }

  @override
  String get descriptionLabel => 'Description';

  @override
  String get editAction => 'Edit';

  @override
  String get noDescriptionHint => 'No description. Tap edit to add one.';

  @override
  String get createdOnLabel => 'Created on';

  @override
  String get yourRole => 'Your role';

  @override
  String get administratorRole => 'Administrator';

  @override
  String get memberRole => 'Member';

  @override
  String get founderLabel => 'Founder';

  @override
  String get youCreatedThisGroup => 'You created this group';

  @override
  String get editGroup => 'Edit group';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get descriptionHint => 'Describe your group...';

  @override
  String get nameMinThreeChars => 'Name must be at least 3 characters';

  @override
  String get regenerateCodeTitle => 'Regenerate code';

  @override
  String get regenerateCodeDesc =>
      'The old code will no longer work. Do you want to generate a new invite code?';

  @override
  String get regenerateAction => 'Regenerate';

  @override
  String newCodeSnack(String code) {
    return 'New code: $code';
  }

  @override
  String get codeCopied => 'Code copied!';

  @override
  String groupNowIs(String visibility) {
    return 'Group is now $visibility';
  }

  @override
  String inviteShareText(String name, String code) {
    return 'Join the group \"$name\" on TrailShare!\n\nUse the invite code: $code\n\nDownload TrailShare and enter the code in the Community > Groups section.';
  }

  @override
  String get inviteShareSubject => 'TrailShare group invite';

  @override
  String get userLabel => 'User';

  @override
  String get leaveGroupTitle => 'Leave group';

  @override
  String get deleteGroupMenu => 'Delete group';

  @override
  String get monthLowerGen => 'Jan';

  @override
  String get monthLowerFeb => 'Feb';

  @override
  String get monthLowerMar => 'Mar';

  @override
  String get monthLowerApr => 'Apr';

  @override
  String get monthLowerMag => 'May';

  @override
  String get monthLowerGiu => 'Jun';

  @override
  String get monthLowerLug => 'Jul';

  @override
  String get monthLowerAgo => 'Aug';

  @override
  String get monthLowerSet => 'Sep';

  @override
  String get monthLowerOtt => 'Oct';

  @override
  String get monthLowerNov => 'Nov';

  @override
  String get monthLowerDic => 'Dec';

  @override
  String get groupNameHint => 'E.g. Mountain Hikers';

  @override
  String get enterGroupName => 'Enter a name for the group';

  @override
  String get whatDoesYourGroupDo => 'What does your group do?';

  @override
  String get visibilityLabel => 'Visibility';

  @override
  String get publicVisibilityDescFull => 'Visible to everyone, anyone can join';

  @override
  String get privateVisibilityDescFull =>
      'Visible to everyone, admin approval required';

  @override
  String get secretVisibilityDescFull =>
      'Hidden, accessible only via invite code';

  @override
  String get groupCreated => 'Group created!';

  @override
  String get groupCreationError => 'Error creating the group';

  @override
  String get eventLabel => 'Event';

  @override
  String get deletePost => 'Delete post';

  @override
  String get deletePostConfirm => 'Do you want to delete this post?';

  @override
  String get deleteEvent => 'Delete event';

  @override
  String get deleteEventConfirm =>
      'Do you want to delete this event? This action is irreversible.';

  @override
  String get changeCover => 'Change cover';

  @override
  String get addCover => 'Add cover';

  @override
  String participantsWithMax(String count, String max) {
    return 'Participants ($count/$max)';
  }

  @override
  String participantsOnly(String count) {
    return 'Participants ($count)';
  }

  @override
  String get noParticipantsYet => 'No participants yet';

  @override
  String get enrolledWithdraw => 'Enrolled — Withdraw';

  @override
  String get eventFull => 'Event is full';

  @override
  String get participate => 'Join';

  @override
  String get updatesLabel => 'Updates';

  @override
  String get writeUpdate => 'Write an update...';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get publish => 'Publish';

  @override
  String get noUpdates => 'No updates';

  @override
  String get shareEventPhotos => 'Share info, news or photos of the event!';

  @override
  String get justNow => 'Now';

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get concluded => 'Ended';

  @override
  String organizedBy(String name) {
    return 'Organized by $name';
  }

  @override
  String get photoEmoji => '📷 Photo';

  @override
  String get deleteEventMenu => 'Delete event';

  @override
  String uploadError(String error) {
    return 'Upload error: $error';
  }

  @override
  String get monthFullJan => 'January';

  @override
  String get monthFullFeb => 'February';

  @override
  String get monthFullMar => 'March';

  @override
  String get monthFullApr => 'April';

  @override
  String get monthFullMay => 'May';

  @override
  String get monthFullJun => 'June';

  @override
  String get monthFullJul => 'July';

  @override
  String get monthFullAug => 'August';

  @override
  String get monthFullSep => 'September';

  @override
  String get monthFullOct => 'October';

  @override
  String get monthFullNov => 'November';

  @override
  String get monthFullDec => 'December';

  @override
  String sendImageError(String error) {
    return 'Error sending image: $error';
  }

  @override
  String yesterdayAtTime(String time) {
    return 'Yesterday $time';
  }

  @override
  String get upcomingFilter => 'Upcoming';

  @override
  String get allFilter => 'All';

  @override
  String get noEventsTitle => 'No events';

  @override
  String get organizeAnOuting => 'Organize an outing!';

  @override
  String get pastLabel => 'Past';

  @override
  String get withdraw => 'Withdraw';

  @override
  String participantsCountWithMax(String count, String max) {
    return '$count/$max participants';
  }

  @override
  String participantsCountSimple(String count) {
    return '$count participants';
  }

  @override
  String get createFirstGroup => 'Create your first group';

  @override
  String get myGroupsTab => 'My Groups';

  @override
  String get newChallenge => 'New Challenge';

  @override
  String get challengeTitleRequired => 'Challenge title *';

  @override
  String get challengeTitleHint => 'E.g. Who covers the most km this week?';

  @override
  String get challengeTypeRequired => 'Challenge type *';

  @override
  String get goalRequired => 'Goal *';

  @override
  String get durationRequired => 'Duration *';

  @override
  String get enterValidGoal => 'Enter a valid goal';

  @override
  String get launchChallenge => 'Launch the Challenge!';

  @override
  String get distanceLabel => 'Distance';

  @override
  String get elevationLabel => 'Elevation';

  @override
  String get consistencyLabel => 'Consistency';

  @override
  String get distanceDesc => 'Who covers the most km';

  @override
  String get elevationDesc => 'Who accumulates the most meters';

  @override
  String get tracksDesc => 'Who records the most outings';

  @override
  String get consistencyDesc => 'Most consecutive days';

  @override
  String get distanceHint => 'E.g. 50 (km)';

  @override
  String get elevationHint => 'E.g. 2000 (meters)';

  @override
  String get tracksHint => 'E.g. 10 (tracks)';

  @override
  String get streakHint => 'E.g. 7 (days)';

  @override
  String get suffixTracks => 'tracks';

  @override
  String get suffixDays => 'days';

  @override
  String get threeDays => '3 days';

  @override
  String get oneWeek => '1 week';

  @override
  String get twoWeeks => '2 weeks';

  @override
  String get oneMonth => '1 month';

  @override
  String challengeInfoText(int days) {
    return 'The challenge starts today and lasts $days days. Progress is calculated automatically from recorded tracks.';
  }

  @override
  String get challengeCreatedShort => 'Challenge created!';

  @override
  String get challengeCreationError => 'Error creating the challenge';

  @override
  String get newEvent => 'New Event';

  @override
  String get titleRequired => 'Title *';

  @override
  String get eventTitleHint => 'E.g. Hike to Mountain Refuge';

  @override
  String get dateAndTime => 'Date and time *';

  @override
  String get outingDetails => 'Details about the outing...';

  @override
  String get meetingPoint => 'Meeting point';

  @override
  String get meetingPointHint => 'E.g. Central parking lot';

  @override
  String get routeDetails => 'Route details';

  @override
  String get difficultyLabel => 'Difficulty';

  @override
  String get mediumDifficulty => 'Medium';

  @override
  String get expertDifficulty => 'Expert';

  @override
  String get maxParticipantsLabel => 'Maximum participants';

  @override
  String get notesLabel => 'Notes';

  @override
  String get notesHint =>
      'E.g. Bring packed lunch, trekking poles recommended...';

  @override
  String get eventCreatedSnack => 'Event created!';

  @override
  String get distanceHintShort => 'Distance';

  @override
  String get elevationHintShort => 'Elevation';

  @override
  String get activeFilter => 'Active';

  @override
  String get allChallengesFilter => 'All';

  @override
  String get noChallenges => 'No challenges';

  @override
  String get launchGroupChallenge => 'Launch a challenge to the group!';

  @override
  String get lastDay => 'Last day!';

  @override
  String daysLeftCount(int count) {
    return '$count days';
  }

  @override
  String get concludedFemale => 'Ended';

  @override
  String createdByFemale(String name) {
    return 'Created by $name';
  }

  @override
  String goalColon(String value) {
    return 'Goal: $value';
  }

  @override
  String typeAndGoal(String type, String goal) {
    return '$type • Goal: $goal';
  }

  @override
  String get suffixDaysShort => 'd';

  @override
  String membersWithCount(int count) {
    return 'Members ($count)';
  }

  @override
  String get inviteTooltip => 'Invite';

  @override
  String get removeMember => 'Remove member';

  @override
  String removeMemberConfirm(String name) {
    return 'Do you want to remove $name from the group?';
  }

  @override
  String get removeAction => 'Remove';

  @override
  String get youSuffix => ' (you)';

  @override
  String get adminWithCrown => '👑 Administrator';

  @override
  String get allContactsInGroup => 'All your contacts are already in the group';

  @override
  String get inviteContact => 'Invite a contact';

  @override
  String addedToGroup(String name) {
    return '$name added to the group!';
  }

  @override
  String get inviteAction => 'Invite';

  @override
  String get shareTooltip => 'Share';

  @override
  String get publishToCommunity => 'Publish to community';

  @override
  String get elevationGainLabel => 'Elevation +';

  @override
  String photosCount(int count) {
    return '📸 $count photos';
  }

  @override
  String get publishedBadge => 'Public';

  @override
  String get dateLabel => 'Date';

  @override
  String get gpsPoints => 'GPS Points';

  @override
  String get maxElevation => 'Max elevation';

  @override
  String get minElevation => 'Min elevation';

  @override
  String get caloriesLabel => 'Calories';

  @override
  String get stepsLabel => 'Steps';

  @override
  String get activityLabel => 'Activity';

  @override
  String get changeActivity => 'Change activity';

  @override
  String get onFoot => 'On foot';

  @override
  String get byBicycle => 'By bicycle';

  @override
  String get winterSports => 'Winter sports';

  @override
  String get nameLabel => 'Name';

  @override
  String get addDescription => 'Add a description...';

  @override
  String get nameCannotBeEmpty => 'Name cannot be empty';

  @override
  String get trackUpdated => '✅ Track updated!';

  @override
  String get publishToCommunityTitle => 'Publish to community';

  @override
  String get publishCommunityDesc =>
      'Your track will be visible to all users in the \"Discover\" section.';

  @override
  String get publishAction => 'Publish';

  @override
  String get heartRateTitle => 'Heart rate data';

  @override
  String get searchHRFromWatch => 'Tap to search HR data from your smartwatch';

  @override
  String get searchingHR => '🔍 Searching heart rate data...';

  @override
  String hrSamplesFound(int count) {
    return '❤️ $count HR samples found!';
  }

  @override
  String get noHRFound =>
      'No HR data found. Make sure your smartwatch has synced with Health Connect.';

  @override
  String get hrRetrievalError => 'Error retrieving HR data';

  @override
  String get mustBeLoggedIn => 'You must be logged in';

  @override
  String get trackPublished => '✅ Track published to community!';

  @override
  String get publishFailed => 'Publication failed';

  @override
  String get unpublishTitle => 'Remove from community';

  @override
  String get unpublishDesc =>
      'The track will no longer be visible in the \"Discover\" section. You can republish it at any time.';

  @override
  String get trackUnpublished => 'Track removed from community';

  @override
  String get deleteTrackTitle => 'Delete track';

  @override
  String get deleteTrackIrreversible =>
      'This action is irreversible. The track will be permanently deleted.';

  @override
  String get downloadTooltip => 'Download';

  @override
  String get quotaLabel => 'Elevation';

  @override
  String get positionLabel => 'Position';

  @override
  String get timeLabel => 'Time';

  @override
  String get photoInfo => 'Photo Information';

  @override
  String get latitudeLabel => 'Latitude';

  @override
  String get longitudeLabel => 'Longitude';

  @override
  String photoFrom(String name) {
    return 'Photo from $name';
  }

  @override
  String get downloadError => 'Download error';

  @override
  String get errorLabel => 'Error';

  @override
  String get editMenu => 'Edit';

  @override
  String get detailsHeader => 'Details';

  @override
  String get durationStatLabel => 'Duration';

  @override
  String activityChangedTo(String name) {
    return 'Activity changed to $name';
  }

  @override
  String get publishDialogContent =>
      'Your track will be visible to all users in the \"Discover\" section.';

  @override
  String get heartRateDataTitle => 'Heart rate data';

  @override
  String get tapToSearchHR => 'Tap to search HR data from your smartwatch';

  @override
  String get noHRData =>
      'No HR data found. Make sure your smartwatch has synced with Health Connect.';

  @override
  String get unpublishContent =>
      'The track will no longer be visible in the \"Discover\" section. You can republish it at any time.';

  @override
  String get deleteTrackContent =>
      'This action is irreversible. The track will be permanently deleted.';

  @override
  String get elevationLossLabel => 'Elevation loss';

  @override
  String get photoInfoTitle => 'Photo Info';

  @override
  String get dateInfoLabel => 'Date';

  @override
  String get timeInfoLabel => 'Time';

  @override
  String get elevationQuotaLabel => 'Altitude';

  @override
  String get captionLabel => 'Description';

  @override
  String get quotaMetadata => 'Altitude';

  @override
  String get positionMetadata => 'Position';

  @override
  String get timeMetadata => 'Time';

  @override
  String get listTab => 'List';

  @override
  String get planTab => 'Plan';

  @override
  String get loginToSeeTracks => 'Log in to see your tracks';

  @override
  String loadingErrorWithDetails(String error) {
    return 'Loading error: $error';
  }

  @override
  String get noTracksSaved => 'No saved tracks';

  @override
  String get startRecordingAdventures => 'Start recording your adventures!';

  @override
  String get loginToPlan => 'Log in to plan tracks';

  @override
  String get mapAction => 'Map';

  @override
  String deleteTrackConfirmName(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get plannedBadge => 'PLANNED';

  @override
  String todayAtTime(String time) {
    return 'Today $time';
  }

  @override
  String get cannotReadFile =>
      'Cannot read the file. Make sure it is a valid GPX or FIT file.';

  @override
  String get cannotReadGpx =>
      'Cannot read the GPX file. Make sure it is a valid file.';

  @override
  String get importGpxTitle => 'Import a GPX file';

  @override
  String get selectGpxFromDevice => 'Select a .gpx file from your device';

  @override
  String get selectGpxFile => 'Select GPX file';

  @override
  String get activityTypeLabel => 'Activity type';

  @override
  String get changeFile => 'Change';

  @override
  String get trackImported => '✅ Track imported successfully!';

  @override
  String saveErrorWithDetails(String error) {
    return 'Save error: $error';
  }

  @override
  String get noGpsData => 'No GPS data';

  @override
  String get elevationGainShort => 'Elevation gain';

  @override
  String get cannotCalculateRoute =>
      'Cannot calculate the route. Please retry.';

  @override
  String get addAtLeast2Points => 'Add at least 2 points to the route';

  @override
  String get loginToSave => 'You must log in to save';

  @override
  String get routeSaved => 'Route saved! 🎉';

  @override
  String get tapMapToStart => 'Tap the map to start';

  @override
  String waypointCount(int count) {
    return '$count points';
  }

  @override
  String get waypointSingle => '1 point';

  @override
  String get longPressToRemove => 'Long press to remove';

  @override
  String get addPointsToCreate => 'Add points to create a route';

  @override
  String get calculatingRouteHiking => 'Calculating hiking route...';

  @override
  String get calculatingRouteCycling => 'Calculating cycling route...';

  @override
  String get ascentLabel => 'Ascent';

  @override
  String get descentLabel => 'Descent';

  @override
  String get timeEstLabel => 'Time';

  @override
  String get clearRoute => 'Clear route';

  @override
  String get clearRouteConfirm => 'Do you want to clear all points?';

  @override
  String get clearAction => 'Clear';

  @override
  String get saveRoute => 'Save route';

  @override
  String get routeName => 'Route name';

  @override
  String get enterAName => 'Enter a name';

  @override
  String get hikeDefaultName => 'Hike';

  @override
  String get bikeDefaultName => 'Bike ride';

  @override
  String get recordLabel => 'Record';

  @override
  String get tracksNavLabel => 'Tracks';

  @override
  String discoverWithCount(int count) {
    return 'Discover ($count)';
  }

  @override
  String get loadingTrails => 'Loading trails...';

  @override
  String trailsUpdating(int count) {
    return '$count trails · Updating...';
  }

  @override
  String trailsZoomForDetails(int count) {
    return '$count trails (zoom for details)';
  }

  @override
  String get moveMapToExplore => 'Move the map to explore trails';

  @override
  String trailsInArea(int count) {
    return '$count trails in this area';
  }

  @override
  String get positionBtn => '📍 Position';

  @override
  String noResultsFor(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get trailsLabel => 'trails';

  @override
  String get noTrailInArea => 'No trail in this area';

  @override
  String get moveOrZoomMap => 'Move or zoom the map to explore other areas';

  @override
  String get trailFallback => 'Trail';

  @override
  String get circularBadge => 'Circular';

  @override
  String sharedOnDate(String date) {
    return 'Shared on $date';
  }

  @override
  String photosWithCount(int count) {
    return 'Photos ($count)';
  }

  @override
  String get detailsLabel => 'Details';

  @override
  String get sourceLabel => 'Source';

  @override
  String get communitySource => 'Community';

  @override
  String get exporting => 'Exporting...';

  @override
  String get downloadGpx => 'Download GPX';

  @override
  String get alreadyPromoted => 'Already promoted to Trail ✓';

  @override
  String get promotionInProgress => 'Promotion in progress...';

  @override
  String get promoteToTrail => 'Promote to Trail';

  @override
  String get promoteDialogDescription =>
      'This track will be added to public trails and will be visible to all users in the Discover section.';

  @override
  String get authorLabel => 'Author';

  @override
  String get fewGpsPointsWarning =>
      'Few GPS points — the track may be inaccurate';

  @override
  String get promote => 'Promote';

  @override
  String get trackPromotedSuccess => '✅ Track promoted to public trail!';

  @override
  String get promotionFailed => 'Promotion failed';

  @override
  String get noGpsPointsToExport => 'No GPS points to export';

  @override
  String gpxTrackName(String name) {
    return 'GPX Track: $name';
  }

  @override
  String get gpxExported => '✅ GPX exported!';

  @override
  String get cannotLoadImage => 'Cannot load image';

  @override
  String get hikePhoto => 'Hike photo';

  @override
  String get lengthLabel => 'Length';

  @override
  String get informationLabel => 'Information';

  @override
  String get trailNumber => 'Trail number';

  @override
  String get managerLabel => 'Manager';

  @override
  String get networkLabel => 'Network';

  @override
  String get regionLabel => 'Region';

  @override
  String get openStreetMapSource => 'OpenStreetMap';

  @override
  String get followTrail => 'Follow the trail';

  @override
  String get navigateToStart => 'Navigate to start point';

  @override
  String get deleteTrailTitle => 'Delete trail';

  @override
  String get deleteTrailConfirmIntro => 'You are about to permanently delete:';

  @override
  String get deleteTrailIrreversible =>
      'This action is irreversible and will remove the trail from the map for all users.';

  @override
  String trailDeletedName(String name) {
    return '✅ \"$name\" deleted';
  }

  @override
  String deleteErrorWithDetails(String error) {
    return 'Delete error: $error';
  }

  @override
  String get loadingTrailWait => 'Loading track, please wait...';

  @override
  String get loadingRetryLater => 'Loading in progress, try again shortly...';

  @override
  String trailGpxName(String name) {
    return 'Trail GPX: $name';
  }

  @override
  String cannotOpenNavigation(String error) {
    return 'Cannot open navigation: $error';
  }

  @override
  String get gpsDisabled => 'GPS disabled';

  @override
  String get gpsPermDenied => 'GPS permission denied';

  @override
  String get gpsPermDeniedPermanently => 'GPS permission permanently denied';

  @override
  String get gpsError => 'GPS error';

  @override
  String get navigationActive => 'Navigation active';

  @override
  String get waitingForGps => 'Waiting for GPS...';

  @override
  String get soundAlertEnabled => '🔊 Sound alert enabled';

  @override
  String get soundAlertDisabled => '🔇 Sound alert disabled';

  @override
  String severeOffTrailDistance(String distance) {
    return 'You are ${distance}m from the trail!';
  }

  @override
  String offTrailDistance(String distance) {
    return 'Off trail (${distance}m)';
  }

  @override
  String get arrivedAtEnd => 'You reached the end of the trail! 🎉';

  @override
  String get seeFullTrail => 'See full trail';

  @override
  String get centerOnMe => 'Center on me';

  @override
  String percentCompleted(String percent) {
    return '$percent% completed';
  }

  @override
  String get remainingLabel => 'Remaining';

  @override
  String get altitudeLabel => 'Altitude';

  @override
  String get fromTrailLabel => 'From trail';

  @override
  String get activeRecording => 'Active recording';

  @override
  String recordedPointsInfo(int count, String duration) {
    return 'You recorded $count points in $duration.\nWhat do you want to do?';
  }

  @override
  String get saveAndExit => 'Save and exit';

  @override
  String get discardAndExit => 'Discard and exit';

  @override
  String get stopNavigation => 'Stop navigation?';

  @override
  String get stopFollowingQuestion =>
      'Do you want to stop following this trail?';

  @override
  String get tooFewPointsToSave => 'Too few points to save';

  @override
  String get mustBeLoggedToSave => 'You must be logged in to save';

  @override
  String get discardRecording => 'Discard recording?';

  @override
  String recordedPointsDiscard(int count) {
    return 'You recorded $count points. Discard them?';
  }

  @override
  String get noSave => 'No, save';

  @override
  String get discardAction => 'Discard';

  @override
  String trackSavedWithCount(String name, int count) {
    return '✅ Track \"$name\" saved! ($count points)';
  }

  @override
  String get saveTrackTitle => 'Save track';

  @override
  String get pointsLabel => 'Points';

  @override
  String get sessionNotFound => 'Session not found or expired';

  @override
  String get inLive => 'LIVE';

  @override
  String get ended => 'ENDED';

  @override
  String lastSignal(String time) {
    return 'Last signal: $time';
  }

  @override
  String get goBack => 'Go back';

  @override
  String get recordingFound => 'Recording found';

  @override
  String get unsavedRecordingFound => 'An unsaved recording was found:';

  @override
  String get wantToRecover => 'Do you want to recover it?';

  @override
  String get recover => 'Recover';

  @override
  String gpsPointsCount(int count) {
    return '📍 $count GPS points';
  }

  @override
  String recoveredGpsPoints(int count) {
    return '✅ Recovered $count GPS points';
  }

  @override
  String get lowBatteryWarning =>
      '⚠️ Low battery! Track will be auto-saved at 5%';

  @override
  String get criticalBatteryWarning => '🔋 Critical battery! Saving track...';

  @override
  String get autoSaved => '(auto-saved)';

  @override
  String get trackAutoSaved => '✅ Track auto-saved!';

  @override
  String uploadingPhotos(int count) {
    return 'Uploading $count photos...';
  }

  @override
  String get restoringRecording => 'Restoring recording...';

  @override
  String get gpsNotAvailable => 'GPS not available';

  @override
  String get photoAdded => '📸 Photo added!';

  @override
  String photosAdded(int count) {
    return '📸 $count photos added!';
  }

  @override
  String get photoDeleted => 'Photo deleted';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get pickFromGallery => 'Pick from gallery';

  @override
  String get cancelRecording => 'Cancel recording?';

  @override
  String get trackDataWillBeLost => 'Current track data will be lost.';

  @override
  String trackAndPhotosWillBeLost(int count) {
    return 'Track data and $count photos will be lost.';
  }

  @override
  String get noPointsRecorded => 'No points recorded';

  @override
  String get stopRecordingError => 'Error stopping the recording';

  @override
  String photosNotUploaded(int count) {
    return '⚠️ $count photos not uploaded';
  }

  @override
  String get paused => 'PAUSED';

  @override
  String get speedLabel => 'Speed';

  @override
  String get avgSpeedLabel => 'Avg';

  @override
  String get paceLabel => 'Pace';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get pauseLabel => 'Pause';

  @override
  String get resumeLabel => 'Resume';

  @override
  String get saveLabel => 'Save';

  @override
  String get motivational1 => 'Great job! 💪';

  @override
  String get motivational2 => 'Amazing hike! 🏔️';

  @override
  String get motivational3 => 'Fantastic trail! 🥾';

  @override
  String get motivational4 => 'What an adventure! 🌟';

  @override
  String get motivational5 => 'You\'re a true explorer! 🧭';

  @override
  String get motivational6 => 'Trail completed! 🎯';

  @override
  String get motivational7 => 'Well done, keep going! 🔥';

  @override
  String get metersDPlus => 'm D+';

  @override
  String get continueBtn => 'Continue';

  @override
  String get chooseActivity => 'Choose activity';

  @override
  String get byCycle => 'By bicycle';

  @override
  String get photosLabel => 'Photos';

  @override
  String get savedTracks => 'Saved Tracks';

  @override
  String get removeFromSaved => 'Remove from saved';

  @override
  String get removeTrackQuestion =>
      'Do you want to remove this track from your list?';

  @override
  String get removeLabel => 'Remove';

  @override
  String get trackRemovedFromSaved => 'Track removed from saved';

  @override
  String get loginToSeeSaved => 'Log in to see your saved tracks';

  @override
  String get saveTracksHint => 'Save the tracks you like to find them easily!';

  @override
  String get loadingError => 'Loading error';

  @override
  String get noSavedTracks => 'No saved tracks';

  @override
  String get exploreSavedHint =>
      'Explore the \"Discover\" section and save the tracks you like!';

  @override
  String get goToDiscover => 'Go to Discover';

  @override
  String get userFallback => 'User';

  @override
  String get gpsAccessError => 'Unable to access GPS. Check permissions.';

  @override
  String get gpsResumeError => 'Unable to resume GPS.';

  @override
  String get locationDisclosureTitle => 'Location access';

  @override
  String get locationDisclosureBody =>
      'TrailShare uses your location to:\n\n• Record GPS tracks of your outdoor activities (hiking, running, cycling)\n• Show nearby trails and points of interest\n• Provide accurate statistics on distance, speed and route\n• Enable background tracking during recording to ensure route continuity even with the screen off\n\nYour location is not shared with third parties, unless you voluntarily publish a track to the community.';

  @override
  String get locationDisclosureDecline => 'Not now';

  @override
  String get locationDisclosureAccept => 'Got it, continue';
}
