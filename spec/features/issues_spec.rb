require 'spec_helper'

describe 'Issues', :js do
  include DropzoneHelper
  include IssueHelpers
  include SortingHelper

  let(:user) { create(:user) }
  let(:project) { create(:project, :public) }

  before do
    sign_in(user)
    user2 = create(:user)

    project.team << [[user, user2], :developer]
  end

  describe 'Edit issue' do
    let!(:issue) do
      create(:issue,
             author: user,
             assignees: [user],
             project: project)
    end

    before do
      visit project_issue_path(project, issue)
      page.within('.content .issuable-actions') do
        find('.issuable-edit').click
      end
      find('.issue-details .content-block .js-zen-enter').click
    end

    it 'opens new issue popup' do
      expect(page).to have_content(issue.description)
    end
  end

  describe 'Issue info' do
    it 'links to current issue in breadcrubs' do
      issue = create(:issue, project: project)

      visit project_issue_path(project, issue)

      expect(find('.breadcrumbs-sub-title a')[:href]).to end_with(issue_path(issue))
    end

    it 'excludes award_emoji from comment count' do
      issue = create(:issue, author: user, assignees: [user], project: project, title: 'foobar')
      create(:award_emoji, awardable: issue)

      visit project_issues_path(project, assignee_id: user.id)

      expect(page).to have_content 'foobar'
      expect(page.all('.no-comments').first.text).to eq "0"
    end
  end

  describe 'Filter issue' do
    before do
      %w(foobar barbaz gitlab).each do |title|
        create(:issue,
               author: user,
               assignees: [user],
               project: project,
               title: title)
      end

      @issue = Issue.find_by(title: 'foobar')
      @issue.milestone = create(:milestone, project: project)
      @issue.assignees = []
      @issue.save
    end

    let(:issue) { @issue }

    it 'allows filtering by issues with no specified assignee' do
      visit project_issues_path(project, assignee_id: IssuableFinder::NONE)

      expect(page).to have_content 'foobar'
      expect(page).not_to have_content 'barbaz'
      expect(page).not_to have_content 'gitlab'
    end

    it 'allows filtering by a specified assignee' do
      visit project_issues_path(project, assignee_id: user.id)

      expect(page).not_to have_content 'foobar'
      expect(page).to have_content 'barbaz'
      expect(page).to have_content 'gitlab'
    end
  end

  describe 'filter issue' do
    titles = %w[foo bar baz]
    titles.each_with_index do |title, index|
      let!(title.to_sym) do
        create(:issue, title: title,
                       project: project,
                       created_at: Time.now - (index * 60))
      end
    end
    let(:newer_due_milestone) { create(:milestone, due_date: '2013-12-11') }
    let(:later_due_milestone) { create(:milestone, due_date: '2013-12-12') }

    it 'sorts by newest' do
      visit project_issues_path(project, sort: sort_value_created_date)

      expect(first_issue).to include('foo')
      expect(last_issue).to include('baz')
    end

    it 'sorts by most recently updated' do
      baz.updated_at = Time.now + 100
      baz.save
      visit project_issues_path(project, sort: sort_value_recently_updated)

      expect(first_issue).to include('baz')
    end

    describe 'sorting by due date' do
      before do
        foo.update(due_date: 1.day.from_now)
        bar.update(due_date: 6.days.from_now)
      end

      it 'sorts by due date' do
        visit project_issues_path(project, sort: sort_value_due_date)

        expect(first_issue).to include('foo')
      end

      it 'sorts by due date by excluding nil due dates' do
        bar.update(due_date: nil)

        visit project_issues_path(project, sort: sort_value_due_date)

        expect(first_issue).to include('foo')
      end

      context 'with a filter on labels' do
        let(:label) { create(:label, project: project) }

        before do
          create(:label_link, label: label, target: foo)
        end

        it 'sorts by least recently due date by excluding nil due dates' do
          bar.update(due_date: nil)

          visit project_issues_path(project, label_names: [label.name], sort: sort_value_due_date_later)

          expect(first_issue).to include('foo')
        end
      end
    end

    describe 'filtering by due date' do
      before do
        foo.update(due_date: 1.day.from_now)
        bar.update(due_date: 6.days.from_now)
      end

      it 'filters by none' do
        visit project_issues_path(project, due_date: Issue::NoDueDate.name)

        page.within '.issues-holder' do
          expect(page).not_to have_content('foo')
          expect(page).not_to have_content('bar')
          expect(page).to have_content('baz')
        end
      end

      it 'filters by any' do
        visit project_issues_path(project, due_date: Issue::AnyDueDate.name)

        page.within '.issues-holder' do
          expect(page).to have_content('foo')
          expect(page).to have_content('bar')
          expect(page).to have_content('baz')
        end
      end

      it 'filters by due this week' do
        foo.update(due_date: Date.today.beginning_of_week + 2.days)
        bar.update(due_date: Date.today.end_of_week)
        baz.update(due_date: Date.today - 8.days)

        visit project_issues_path(project, due_date: Issue::DueThisWeek.name)

        page.within '.issues-holder' do
          expect(page).to have_content('foo')
          expect(page).to have_content('bar')
          expect(page).not_to have_content('baz')
        end
      end

      it 'filters by due this month' do
        foo.update(due_date: Date.today.beginning_of_month + 2.days)
        bar.update(due_date: Date.today.end_of_month)
        baz.update(due_date: Date.today - 50.days)

        visit project_issues_path(project, due_date: Issue::DueThisMonth.name)

        page.within '.issues-holder' do
          expect(page).to have_content('foo')
          expect(page).to have_content('bar')
          expect(page).not_to have_content('baz')
        end
      end

      it 'filters by overdue' do
        foo.update(due_date: Date.today + 2.days)
        bar.update(due_date: Date.today + 20.days)
        baz.update(due_date: Date.yesterday)

        visit project_issues_path(project, due_date: Issue::Overdue.name)

        page.within '.issues-holder' do
          expect(page).not_to have_content('foo')
          expect(page).not_to have_content('bar')
          expect(page).to have_content('baz')
        end
      end
    end

    describe 'sorting by milestone' do
      before do
        foo.milestone = newer_due_milestone
        foo.save
        bar.milestone = later_due_milestone
        bar.save
      end

      it 'sorts by milestone' do
        visit project_issues_path(project, sort: sort_value_milestone)

        expect(first_issue).to include('foo')
        expect(last_issue).to include('baz')
      end
    end

    describe 'combine filter and sort' do
      let(:user2) { create(:user) }

      before do
        foo.assignees << user2
        foo.save
        bar.assignees << user2
        bar.save
      end

      it 'sorts with a filter applied' do
        visit project_issues_path(project, sort: sort_value_created_date, assignee_id: user2.id)

        expect(first_issue).to include('foo')
        expect(last_issue).to include('bar')
        expect(page).not_to have_content('baz')
      end
    end
  end

  describe 'when I want to reset my incoming email token' do
    let(:project1) { create(:project, namespace: user.namespace) }
    let!(:issue) { create(:issue, project: project1) }

    before do
      stub_incoming_email_setting(enabled: true, address: "p+%{key}@gl.ab")
      project1.team << [user, :master]
      visit namespace_project_issues_path(user.namespace, project1)
    end

    it 'changes incoming email address token', js: true do
      find('.issue-email-modal-btn').click
      previous_token = find('input#issue_email').value
      find('.incoming-email-token-reset').click

      wait_for_requests

      expect(page).to have_no_field('issue_email', with: previous_token)
      new_token = project1.new_issue_address(user.reload)
      expect(page).to have_field(
        'issue_email',
        with: new_token
      )
    end
  end

  describe 'update labels from issue#show', js: true do
    let(:issue) { create(:issue, project: project, author: user, assignees: [user]) }
    let!(:label) { create(:label, project: project) }

    before do
      visit project_issue_path(project, issue)
    end

    it 'will not send ajax request when no data is changed' do
      page.within '.labels' do
        click_link 'Edit'

        find('.dropdown-menu-close', match: :first).click

        expect(page).not_to have_selector('.block-loading')
      end
    end
  end

  describe 'update assignee from issue#show' do
    let(:issue) { create(:issue, project: project, author: user, assignees: [user]) }

    context 'by authorized user' do
      it 'allows user to select unassigned', js: true do
        visit project_issue_path(project, issue)

        page.within('.assignee') do
          expect(page).to have_content "#{user.name}"

          click_link 'Edit'
          click_link 'Unassigned'
          first('.title').click
          expect(page).to have_content 'No assignee'
        end

        # wait_for_requests does not work with vue-resource at the moment
        sleep 1

        expect(issue.reload.assignees).to be_empty
      end

      it 'allows user to select an assignee', js: true do
        issue2 = create(:issue, project: project, author: user)
        visit project_issue_path(project, issue2)

        page.within('.assignee') do
          expect(page).to have_content "No assignee"
        end

        page.within '.assignee' do
          click_link 'Edit'
        end

        page.within '.dropdown-menu-user' do
          click_link user.name
        end

        page.within('.assignee') do
          expect(page).to have_content user.name
        end
      end

      it 'allows user to unselect themselves', js: true do
        issue2 = create(:issue, project: project, author: user)
        visit project_issue_path(project, issue2)

        page.within '.assignee' do
          click_link 'Edit'
          click_link user.name

          page.within '.value .author' do
            expect(page).to have_content user.name
          end

          click_link 'Edit'
          click_link user.name

          page.within '.value .assign-yourself' do
            expect(page).to have_content "No assignee"
          end
        end
      end
    end

    context 'by unauthorized user' do
      let(:guest) { create(:user) }

      before do
        project.team << [[guest], :guest]
      end

      it 'shows assignee text', js: true do
        sign_out(:user)
        sign_in(guest)

        visit project_issue_path(project, issue)
        expect(page).to have_content issue.assignees.first.name
      end
    end
  end

  describe 'update milestone from issue#show' do
    let!(:issue) { create(:issue, project: project, author: user) }
    let!(:milestone) { create(:milestone, project: project) }

    context 'by authorized user' do
      it 'allows user to select unassigned', js: true do
        visit project_issue_path(project, issue)

        page.within('.milestone') do
          expect(page).to have_content "None"
        end

        find('.block.milestone .edit-link').click
        sleep 2 # wait for ajax stuff to complete
        first('.dropdown-content li').click
        sleep 2
        page.within('.milestone') do
          expect(page).to have_content 'None'
        end

        expect(issue.reload.milestone).to be_nil
      end

      it 'allows user to de-select milestone', js: true do
        visit project_issue_path(project, issue)

        page.within('.milestone') do
          click_link 'Edit'
          click_link milestone.title

          page.within '.value' do
            expect(page).to have_content milestone.title
          end

          click_link 'Edit'
          click_link milestone.title

          page.within '.value' do
            expect(page).to have_content 'None'
          end
        end
      end
    end

    context 'by unauthorized user' do
      let(:guest) { create(:user) }

      before do
        project.team << [guest, :guest]
        issue.milestone = milestone
        issue.save
      end

      it 'shows milestone text', js: true do
        sign_out(:user)
        sign_in(guest)

        visit project_issue_path(project, issue)
        expect(page).to have_content milestone.title
      end
    end
  end

  describe 'new issue' do
    let!(:issue) { create(:issue, project: project) }

    context 'by unauthenticated user' do
      before do
        sign_out(:user)
      end

      it 'redirects to signin then back to new issue after signin' do
        visit project_issues_path(project)

        page.within '.nav-controls' do
          click_link 'New issue'
        end

        expect(current_path).to eq new_user_session_path

        gitlab_sign_in(create(:user))

        expect(current_path).to eq new_project_issue_path(project)
      end
    end

    context 'dropzone upload file', js: true do
      before do
        visit new_project_issue_path(project)
      end

      it 'uploads file when dragging into textarea' do
        dropzone_file Rails.root.join('spec', 'fixtures', 'banana_sample.gif')

        expect(page.find_field("issue_description").value).to have_content 'banana_sample'
      end

      it "doesn't add double newline to end of a single attachment markdown" do
        dropzone_file Rails.root.join('spec', 'fixtures', 'banana_sample.gif')

        expect(page.find_field("issue_description").value).not_to match /\n\n$/
      end
    end

    context 'form filled by URL parameters' do
      let(:project) { create(:project, :public, :repository) }

      before do
        project.repository.create_file(
          user,
          '.gitlab/issue_templates/bug.md',
          'this is a test "bug" template',
          message: 'added issue template',
          branch_name: 'master')

        visit new_project_issue_path(project, issuable_template: 'bug')
      end

      it 'fills in template' do
        expect(find('.js-issuable-selector .dropdown-toggle-text')).to have_content('bug')
      end
    end
  end

  describe 'new issue by email' do
    shared_examples 'show the email in the modal' do
      let(:issue) { create(:issue, project: project) }

      before do
        project.issues << issue
        stub_incoming_email_setting(enabled: true, address: "p+%{key}@gl.ab")

        visit project_issues_path(project)
        click_button('Email a new issue')
      end

      it 'click the button to show modal for the new email' do
        page.within '#issue-email-modal' do
          email = project.new_issue_address(user)

          expect(page).to have_selector("input[value='#{email}']")
        end
      end
    end

    context 'with existing issues' do
      let!(:issue) { create(:issue, project: project, author: user) }

      it_behaves_like 'show the email in the modal'
    end

    context 'without existing issues' do
      it_behaves_like 'show the email in the modal'
    end
  end

  describe 'due date' do
    context 'update due on issue#show', js: true do
      let(:issue) { create(:issue, project: project, author: user, assignees: [user]) }

      before do
        visit project_issue_path(project, issue)
      end

      it 'adds due date to issue' do
        date = Date.today.at_beginning_of_month + 2.days

        page.within '.due_date' do
          click_link 'Edit'

          page.within '.pika-single' do
            click_button date.day
          end

          wait_for_requests

          expect(find('.value').text).to have_content date.strftime('%b %-d, %Y')
        end
      end

      it 'removes due date from issue' do
        date = Date.today.at_beginning_of_month + 2.days

        page.within '.due_date' do
          click_link 'Edit'

          page.within '.pika-single' do
            click_button date.day
          end

          wait_for_requests

          expect(page).to have_no_content 'No due date'

          click_link 'remove due date'
          expect(page).to have_content 'No due date'
        end
      end
    end
  end

  describe 'title issue#show', js: true do
    it 'updates the title', js: true do
      issue = create(:issue, author: user, assignees: [user], project: project, title: 'new title')

      visit project_issue_path(project, issue)

      expect(page).to have_text("new title")

      issue.update(title: "updated title")

      wait_for_requests
      expect(page).to have_text("updated title")
    end
  end

  describe 'confidential issue#show', js: true do
    it 'shows confidential sibebar information as confidential and can be turned off' do
      issue = create(:issue, :confidential, project: project)

      visit project_issue_path(project, issue)

      expect(page).to have_css('.confidential-issue-warning')
      expect(page).to have_css('.is-confidential')
      expect(page).not_to have_css('.is-not-confidential')

      find('.confidential-edit').click
      expect(page).to have_css('.confidential-warning-message')

      within('.confidential-warning-message') do
        find('.btn-close').click
      end

      wait_for_requests

      visit project_issue_path(project, issue)

      expect(page).not_to have_css('.is-confidential')
    end
  end
end
