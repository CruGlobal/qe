//= require fe/fe.common.js

// used by answer sheets

(function($) {
  //debugger;
  $(function() {

    $(document).on('click', '.save_button', function() {
      fe.pageHandler.savePage($(this).closest('.answer-page'), true);
    });

    $(document).on('click', '.reference_send_invite', function() {
      var el = this;
      var form_elements = $(el).closest('form').find('input:not(.dont_submit), textarea:not(.dont_submit), select:not(.dont_submit)');
      var data = form_elements.serializeArray();

      data.push({name: 'answer_sheet_type', value: answer_sheet_type});
      $.ajax({url: $(el).attr('href'), data: data, dataType: 'script',  type: 'POST',
             beforeSend: function (xhr) {
               $('body').trigger('ajax:loading', xhr);
             },
             complete: function (xhr) {
               $('body').trigger('ajax:complete', xhr);
             },
             error: function (xhr, status, error) {
               $('body').trigger('ajax:failure', [xhr, status, error]);
             }
      });
      return false;
    });
    $(document).on('focus', 'textarea[maxlength]', function() {
      var max = parseInt($(this).attr('maxlength'));
      $(this).parent().find('.charsRemaining').html('You have ' + (max - $(this).val().length) + ' characters remaining');
    }).on('keyup', 'textarea[maxlength]', function(){
      var max = parseInt($(this).attr('maxlength'));
      if($(this).val().length > max){
        $(this).val($(this).val().substr(0, $(this).attr('maxlength')));
      }
      $(this).parent().find('.charsRemaining').html('You have ' + (max - $(this).val().length) + ' characters remaining');
    }).on('blur', 'textarea[maxlength]', function() {
      $(this).parent().find('.charsRemaining').html('');
    });
  });

  window.fe = {};
  fe.pageHandler = {

    initialize : function(page) {
      this.auto_save_frequency = 30;  // seconds
      this.timer_id = null;

      this.current_page = page;
      $('#' + page).data('form_data', this.captureForm($('#' + page)));
      this.registerAutoSave();

      this.page_validation = {};  // validation objects for each page
      this.enableValidation(page);

      $(document).trigger('feShowPage'); // allow other code to handle show page event by using $(document).on('feShowPage', function() { ... });

      // this.background_load = false;
      // this.final_submission = false;
    },

    // swap to a different page
    showPage : function(page) {
      // hide the old
      $('#' + this.current_page + '-li').removeClass('active'); 
      $('#' + this.current_page).hide();

      // HACK: Need to clear the main error message when returning to the submit page
      //       It is very confusing to users to be there when they revisit the page
      $('#submit_message, .submit_message').hide(); 
      $('#application_errors, .application_errors').html('');

      // show the new
      // $('#' + page + '-li').removeClass('incomplete');
      // $('#' + page + '-li').removeClass('valid');
      $('#' + page + '-li').addClass('active');
      $('#' + page).show();
      this.current_page = page;
      this.registerAutoSave(page);
      fixGridColumnWidths();
      $(document).trigger('feShowPage'); // allow other code to handle show page event by using $(document).on('feShowPage', function() { ... });
    },

    // callback onSuccess
    pageLoadedBackground : function(response, textStatus, jqXHR) {
      //this.pageLoaded(response, textStatus, jqXHR, true)
      fe.pageHandler.pageLoaded(response, textStatus, jqXHR, true)
    },

    // callback onSuccess
    pageLoaded : function(response, textStatus, jqXHR, background_load) {
      background_load = typeof background_load !== 'undefined' ? background_load : false;

      // var response = new String(transport.responseText);
      var match = response.match(/<div id=\"(.*?)\"/i); // what did I just load? parse out the first div id
      if( match != null )
        {
          var page = match[1];
          if ($('#'+page).length > 0) {
            $('#'+page).replaceWith(response);
          } else {
            $('#preview').append(response);
          }

          if (!background_load) { fe.pageHandler.showPage(page); } // show after load, unless loading in background
          setUpJsHelpers();
          fe.pageHandler.enableValidation(page);
          if (background_load) { fe.pageHandler.validatePage(page, true); }
          $('#' + page).data('form_data', fe.pageHandler.captureForm($('#' + page)));
        }
        $('#page_ajax_spinner').hide();
        $('.reference_send_invite').button();
        updateTotals();
        $(document).trigger('fePageLoaded'); // allow other code to handle page load event by using $(document).on('fePageLoaded', function() { ... });
    },

    loadPage : function(page, url, background_load, validate_current_page) {
      background_load = typeof background_load !== 'undefined' ? background_load : false;
      validate_current_page = typeof validate_current_page !== 'undefined' ? validate_current_page : true;

      if (validate_current_page) {
        isValid = this.validatePage(this.current_page);   // mark current page as valid (or not) as we're leaving
      } else {
        isValid = true
      }

      // Provide a way for enclosing apps to not go to the next page until the current page is valid
      // They can do that with this:
      //
      //     $(document).on 'fePageLoaded', (evt, page) ->
      //        $(".page > form").addClass('enforce-valid-before-next');
      //
      if (!isValid && $('#' + this.current_page + "-form").hasClass('enforce-valid-before-next')) {
        // scroll up to where the error is
        scrollTo($(".help-block:visible")[0].closest("li"));
        return;
      }

      this.unregisterAutoSave();  // don't auto-save while loading/saving
      // will register auto-save on new page once loaded/shown

      this.savePage();

      if (!background_load) { 
        if ($('a[name="main"]').length == 1) {
          scrollTo('a[name="main"]');
        } else {
          scrollTo('#main');
        }
      }

      if (fe.pageHandler.isPageLoaded(page) && page.match('no_cache') == null) {
        // if already loaded (element exists) excluding pages that need reloading
        if (!background_load) { fe.pageHandler.showPage(page); }
        $('#page_ajax_spinner').hide();
      } else {
        $.ajax({
          url: url,
          type: 'GET',
          data: {'answer_sheet_type':answer_sheet_type},
          success: background_load ? fe.pageHandler.pageLoadedBackground : fe.pageHandler.pageLoaded,
          error: function (xhr, status, error) {
            alert("There was a problem loading that page. We've been notified and will fix it as soon as possible. To work on other pages, please refresh the website.");
            document.location = document.location;
          },
          beforeSend: function (xhr) {
            $('body').trigger('ajax:loading', xhr);
          },
          complete: function (xhr) {
            $('body').trigger('ajax:complete', xhr);
          }
        });
      }
    },

    // save form if any changes were made
    savePage : function(page, force, blocking) {

      if (page == null) page = $('#' + this.current_page);
      if (typeof blocking == "undefined") blocking = false;

      // don't save more than once per second
      timeNow = new Date();
      if (typeof(lastSave) != "undefined" && lastSave && !force && (timeNow - lastSave < 1000)) {
        return true;
      }
      lastSave = timeNow;
      form_data = this.captureForm(page);
      if( form_data ) {
        if( page.data('form_data') == null || page.data('form_data').data !== form_data.data || force === true) {  // if any changes
          page.data('form_data', form_data);
          $.ajax({url: form_data.url, type: 'put', data: form_data.data,  
                 beforeSend: function (xhr) {
                   $('#spinner_' + page.attr('id')).show();
                 },
                 complete: function (xhr) {
                   $('#spinner_' + page.attr('id')).hide();
                 },
                 success: function (xhr) {
                   page.data('save_fails', 0)
                 },
                 async: !blocking,
                 error: function() {
                   save_fails = page.data('save_fails') == null ? 0 : page.data('save_fails');
                   save_fails += 1;
                   page.data('save_fails', save_fails)

                   if (save_fails >= 3) {
                     alert("There was a problem saving that page. We've been notified and will fix it as soon as possible. This might happen if you logged out on another tab. The page will now reload.");
                     document.location = document.location;
                   } else {
                     page.data('save_fails', save_fails + 1)
                     page.data('form_data', null);    // on error, force save for next call to save
                     // WARNING: race conditions with load & show?
                     // sort of a mess if save fails while another page is already loading!!
                   }
                 }});
        }
      }
      // Update last saved stamp
    },

    savePages : function(force) {
      $('.answer-page').each(function() {fe.pageHandler.savePage(null, force)})
    },

    // setup a timer to auto-save (only one timer, for the page being viewed)
    registerAutoSave: function(page) {
      this.timer_id = setInterval(this.savePages, this.auto_save_frequency * 1000);
    },

    unregisterAutoSave: function() {
      if( this.timer_id != null ) 
        {
          clearInterval(this.timer_id);
          this.timer_id = null;
        }
    },

    // serialize form data and extract url to post to
    captureForm : function(page) {      
      form_el = $('#' + page.attr('id') + '-form');
      if( form_el[0] == null ) return null;
      form_all_el = form_el.find("input:not(.dont_submit), textarea:not(.dont_submit), select:not(.dont_submit)");
      return {url: form_el.attr('action'), data: form_all_el.serialize() + '&answer_sheet_type=' + answer_sheet_type};
    },


    // enable form validation (when form is loaded)
    enableValidation : function(page) {
      // Provide a way for enclosing apps to not have validation continually as people fill things out
      // They can do that with this:
      //
      //     $(document).on 'fePageLoaded', (evt, page) ->
      //        $(".page > form").addClass('no-ongoing-validation');
      //
      $('#' + page + '-form:not(.no-ongoing-validation)').validate({onsubmit:false, focusInvalid:true, onfocusout: function(element) { this.element(element);}});
      $('#' + page + '-form:not(.no-ongoing-validation):input').change(function() {
        fe.pageHandler.validatePage(page, true);
      });
    },

    validatePage : function(page, page_classes_only) {
      page_classes_only = typeof page_classes_only !== 'undefined' ? page_classes_only : false;

      // Provide a way for enclosing apps to never validate a form
      // They can do that with this:
      //
      //     $(document).on 'fePageLoaded', (evt, page) ->
      //        $(".page > form").addClass('no-validation');
      //
      if ($('#' + this.current_page + "-form").hasClass('no-validation')) { return; }

      try {
        var li = $('#' + page + '-li');
        var form = $('#' + page + '-form');

        valid = form.valid();

        if (!page_classes_only) {
          // Move radio button errors up
          $('input[type=radio].error').closest('tr').addClass('error');
          $('.choice_field input[type=radio].error').removeClass('error')
          .closest('.choice_field')
          .addClass('error');
          $('div.yesno label.error').hide();
        }

        if (valid)  {  
          li.removeClass('incomplete');
          li.addClass('complete');
          $(document).trigger('fePageValid', page); // allow other code to handle show page event by using $(document).on('fePageValid', function() { ... });
        } else {
          li.removeClass('complete');
          li.addClass('incomplete');
          $(document).trigger('fePageInvalid', page); // allow other code to handle show page event by using $(document).on('fePageInvalid', function() { ... });
        }
        return valid;
      }
      catch(err) {

        // If the user clicks too quickly, sometimes the page element isn't properly defined yet.
        // If we don't catch the error, js stops execution. If we catch it, the user just has to click again.
      }
      $('page_ajax_spinner').hide();
    },

    // callback when falls to 0 active Ajax requests
    completeAll : function()
    {
      $('.page:visible #submit_button').attr('disabled', true)
      $('#submit_message, .submit_message').html('');
      $('#submit_message, .submit_message').hide();
      // validate all the pages
      $('.page_link').each(function(index, page) {
        fe.pageHandler.validatePage($(page).attr('data-page-id'));
      });	
      var all_valid = ($('#list-pages li.incomplete').length == 0);

      // Make sure any necessary payments are made
      var payments_made = $('.payment_question.required').length <= $('.payment').length


      if(  payments_made)
        {
          // force an async save (so it finishes before submitting) in case any input fields on submit_page
          this.savePage(null, true, true);

          // submit the application
          if($('#submit_to')[0] != null)
            {
              url = $('#submit_to').val();
              // clear out pages array to force reload.  This enables "frozen" apps
              //       immediately after submission - :onSuccess (for USCM which stays in the application vs. redirecting to the dashboard)
              var curr = fe.pageHandler.current_page;
              $.ajax({url: url, dataType:'script',
                     data: {answer_sheet_type: answer_sheet_type, a: $('input[type=hidden][name=a]').val()},
                     type:'post', 
                     beforeSend: function(xhr) {
                       $('body').trigger('ajax:loading', xhr);
                     },
                     success: function(xhr) {
                       $('#list-pages a').each(function() { 
                         if ($(this).attr('data-page-id') != curr) $('#' + $(this).attr('data-page-id')).remove();
                       })
                     },
                     complete: function(xhr) {
                       $('body').trigger('ajax:complete', xhr);
                       var btn = $('#submit_button'); 
                       if (btn) { btn.attr('disabled', false); }
                     }
              });
            }
        }
        else
          {
            // some pages aren't valid
            $('#submit_message, .submit_message').html("Please make a payment");
            $('#submit_message, .submit_message').show();

            var btn = $('#submit_button'); if (btn) { btn.attr('disabled', false); }
          }
    },

    // is page loaded? (useful for toggling enabled state of questions)
    isPageLoaded : function(page)
    {
      return $('#' + page)[0] != null
    },

    checkConditional : function($element) {
      matchable_answers = String($element.data('conditional_answer')).split(';').map(function(s) { return s.trim(); })
      if ($element.hasClass('fe_choicefield') && ($element.hasClass('style_yes-no') || $element.hasClass('yes-no'))) {
        if ($(matchable_answers).filter([1, '1', true, 'true', 'yes', 'Yes']).length > 0) {
          matchable_answers = [1, '1', true, 'true', 'yes', 'Yes'];
        }
        if ($(matchable_answers).filter([0, '0', false, 'false', 'no', 'No']).length > 0) {
          matchable_answers = [0, '0', false, 'false', 'no', 'No'];
        }
        vals = $([$element.find("input[type=radio]:checked").val()]);
      } else if ($element.hasClass('fe_choicefield') && $element.hasClass('checkbox')) {
        vals = $element.find("input[type=checkbox]:checked").map(function(i, el) { return $(el).val(); });
      } else if ($element.hasClass('fe_choicefield') && $element.hasClass('radio')) {
        vals = $([$element.find("input[type=radio]:checked").val()]);
      } else {
        vals = $([$element.find("input:visible, select:visible").val()]);
      }
      match = $(matchable_answers).filter(vals).length > 0 || (matchable_answers == "" && vals.length == 0);

      switch ($element.data('conditional_type')) {
        case 'Fe::Element':
          if (match) {
            $("#element_" + $element.data('conditional_id')).show(); 
          } else {
            $("#element_" + $element.data('conditional_id')).hide();
          }
          break;
        case 'Fe::Page':
          prefix = $element.data('answer_sheet_id_prefix');
          pg = prefix + '_' + $element.data('application_id') + '-fe_page_' + $element.data('conditional_id');
          li_id = 'li#'+pg+'-li';
          li_id += ', li#'+pg+'-no_cache-li';

          if (match) {
            $(li_id).show();
            // load the page (in the background) to determine validity
            this.loadPage(pg, $(li_id).find('a').attr('href'), true);
          } else {
            $(li_id).hide();
          }
          break;
      }
    },

    next : function(validate_current_page) {
      validate_current_page = typeof validate_current_page !== 'undefined' ? validate_current_page : false;

      curr_page_link = $('#'+fe.pageHandler.current_page+"-link");
      //fe.pageHandler.loadPage('application_22544-fe_page_165-no_cache','/fe/answer_sheets/22544/page/165/edit'); return false;
      page_link = curr_page_link
        .parents('.application_section')
        .nextAll()
        .filter(function() { return $(this).find('a.page_link:visible').length > 0 })
        .first()
        .find('a.page_link');
      $(".answer-page:visible div.buttons button").prop("disabled", true)
      fe.pageHandler.loadPage(page_link.data('page-id'), page_link.attr('href'), false, validate_current_page);
    },

    prev : function() {
      curr_page_link = $('#'+fe.pageHandler.current_page+"-link");
      //fe.pageHandler.loadPage('application_22544-fe_page_165-no_cache','/fe/answer_sheets/22544/page/165/edit'); return false;
      page_link = curr_page_link
        .parents('.application_section')
        .prevAll()
        .filter(function() { return $(this).find('a.page_link:visible').length > 0 })
        .first()
        .find('a.page_link');
      $(".answer-page:visible div.buttons button").prop("disabled", true)
      fe.pageHandler.loadPage(page_link.data('page-id'), page_link.attr('href'));
    }

  };

  $(document).on('click', ".conditional input, .conditional select", function() {
    fe.pageHandler.checkConditional($(this).closest('.conditional'));
  });
  $(document).on('keyup', ".conditional input, .conditional select", function() { $(this).click(); });
  $(document).on('blug', ".conditional input, .conditional select", function() { $(this).click(); });
  $(document).on('change', ".conditional select", function() { $(this).click(); });

  $(document).on('keyup', 'textarea[maxlength]', function() {
    maxlength = parseInt($(this).attr('maxlength'));
    remaining = maxlength - $(this).val().length;
    $('#'+$(this).attr('id')+'_count').val(remaining);
  });

  $(document).on('click', 'a[disabled]', function(event) {
    event.preventDefault();
  });
})(jQuery);

$(function() {
  fixGridColumnWidths();
  setUpCalendars();
});


function updateTotal(id) {
  try {
    total = 0;
    $(".col_" + id).each(function(index, el) {
      total += Number($(el).val().replace(',',''));
    });
    $('#total_' + id).val(total).trigger('totalChanged');
  } catch(e) {
  }
}

function submitToFrame(id, url) {
  form = $('<form method="post" action="'+url+'.js" endtype="multipart/form-data"></form>')
  var csrf_token = $('meta[name=csrf-token]').attr('content'),
  csrf_param = $('meta[name=csrf-param]').attr('content'),
  dom_id = '#attachment_field_' + id,
  metadata_input = '<input name="'+csrf_param+'" value="'+csrf_token+'" type="hidden" />',
  file_field = '<input type="file" name="answers['+ id + ']>';
  if ($(dom_id).val() == '')	return;
  form.hide()
  .append(metadata_input)
  .append(file_field)
  .appendTo('body');
  $(dom_id + "-spinner").show();
  form.submit();
  return false
}

function scrollTo(el) {
  if ($(el).length == 0) { return; }
  $('html, body').animate({
    scrollTop: $(el).offset().top
  }, 1000);
}
